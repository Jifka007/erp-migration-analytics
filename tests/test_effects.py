"""Tests du moteur des effets, sur une petite base fabriquée (jamais le scénario réel)."""

import numpy as np
import pandas as pd
import pytest

from data_generator import effects


@pytest.fixture
def base_order_lines():
    """300 clients (150 en France, 150 en Allemagne), 2 ans de commandes.

    Chaque client commande en moyenne 3 fois par mois (loi de Poisson),
    des quantités entre 10 et 100, dans trois gammes ; 20 % des lignes
    sont des produits du groupe, les autres des produits locaux.
    """
    rng = np.random.default_rng(seed=1)
    months = pd.date_range("2025-01-01", "2026-12-01", freq="MS")
    rows = []
    for customer_number in range(300):
        entity_id = "FR" if customer_number < 150 else "DE"
        for month in months:
            for order in range(rng.poisson(3)):
                rows.append(
                    {
                        "order_number": f"{customer_number}-{month:%Y%m}-{order}",
                        "order_date": month + pd.Timedelta(days=int(rng.integers(0, 28))),
                        "entity_id": entity_id,
                        "customer_id": f"C{customer_number:03d}",
                        "quantity": int(rng.integers(10, 101)),
                        "product_line_id": str(rng.choice(["FOOT", "HAND", "FALL"])),
                        "product_type": "group" if rng.random() < 0.2 else "local",
                    }
                )
    return pd.DataFrame(rows)


GERMANY_DROP = {
    "effect_id": "E_TEST",
    "effect_type": "volume_change",
    "scope": {"entity_id": "DE"},
    "start_date": "2026-01-01",
    "end_date": None,
    "shape": "step",
    "parameters": {"magnitude": -0.15},
}


def test_volume_drops_by_about_15_percent(base_order_lines):
    rng = np.random.default_rng(seed=2)
    modified = effects.apply_volume_change(base_order_lines, GERMANY_DROP, rng)
    in_effect = lambda lines: lines[(lines["entity_id"] == "DE") & (lines["order_date"] >= "2026-01-01")]
    ratio = in_effect(modified)["quantity"].sum() / in_effect(base_order_lines)["quantity"].sum()
    assert ratio == pytest.approx(0.85, abs=0.02)


def test_no_customer_is_lost(base_order_lines):
    rng = np.random.default_rng(seed=2)
    modified = effects.apply_volume_change(base_order_lines, GERMANY_DROP, rng)
    active = lambda lines: lines[lines["order_date"] >= "2026-01-01"]["customer_id"].nunique()
    assert active(modified) == active(base_order_lines)


def test_france_is_untouched(base_order_lines):
    rng = np.random.default_rng(seed=2)
    modified = effects.apply_volume_change(base_order_lines, GERMANY_DROP, rng)
    france = lambda lines: lines[lines["entity_id"] == "FR"]
    assert len(france(modified)) == len(france(base_order_lines))


def test_effect_stands_out_from_noise(base_order_lines):
    rng = np.random.default_rng(seed=2)
    modified = effects.apply_volume_change(base_order_lines, GERMANY_DROP, rng)
    assert effects.signal_to_noise(base_order_lines, modified, GERMANY_DROP) >= 3


def test_ramp_reaches_full_strength_after_ramp_months():
    ramp = {"start_date": "2026-01-01", "shape": "ramp", "ramp_months": 6}
    dates = pd.Series(pd.to_datetime(["2026-01-01", "2026-04-01", "2026-09-01"]))
    strength = effects.effect_strength(dates, ramp)
    assert strength.iloc[0] == 0
    assert 0.4 < strength.iloc[1] < 0.6
    assert strength.iloc[2] == 1


def after_start(lines, entity_id="DE", start="2026-01-01"):
    return lines[(lines["entity_id"] == entity_id) & (lines["order_date"] >= start)]


def test_attrition_removes_about_10_percent_of_customers(base_order_lines):
    effect = {"scope": {"entity_id": "DE"}, "start_date": "2026-01-01", "end_date": None,
              "shape": "step", "parameters": {"lost_customer_share": 0.10}}
    modified = effects.apply_customer_attrition(base_order_lines, effect, np.random.default_rng(3))
    before = after_start(base_order_lines)["customer_id"].nunique()
    after = after_start(modified)["customer_id"].nunique()
    assert after == before - 15


def test_attrition_leaves_remaining_customers_untouched(base_order_lines):
    effect = {"scope": {"entity_id": "DE"}, "start_date": "2026-01-01", "end_date": None,
              "shape": "step", "parameters": {"lost_customer_share": 0.10}}
    modified = effects.apply_customer_attrition(base_order_lines, effect, np.random.default_rng(3))
    remaining = after_start(modified)["customer_id"].unique()
    kept = lambda lines: after_start(lines)[lambda d: d["customer_id"].isin(remaining)]
    assert len(kept(modified)) == len(kept(base_order_lines))


def test_mix_shift_reaches_target_share_without_changing_volume(base_order_lines):
    effect = {"scope": {"entity_id": "DE"}, "start_date": "2026-01-01", "end_date": None,
              "shape": "ramp", "ramp_months": 6,
              "parameters": {"target_products": {"product_type": "group"},
                             "share_start": 0.20, "share_end": 0.35}}
    modified = effects.apply_product_mix_shift(base_order_lines, effect, np.random.default_rng(4))
    end_period = lambda lines: after_start(lines, start="2026-07-01")
    share = (end_period(modified)["product_type"] == "group").mean()
    assert share == pytest.approx(0.35, abs=0.02)
    assert modified["quantity"].sum() == base_order_lines["quantity"].sum()
    assert len(modified) == len(base_order_lines)


def test_demand_transfer_moves_demand_between_lines(base_order_lines):
    effect = {"scope": {"entity_id": "DE"}, "start_date": "2026-01-01", "end_date": None,
              "shape": "step",
              "parameters": {"from_scope": {"product_line_id": "FALL"},
                             "to_scope": {"product_line_id": "HAND"},
                             "transfer_share": 0.30}}
    modified = effects.apply_demand_transfer(base_order_lines, effect, np.random.default_rng(5))
    fall = lambda lines: (after_start(lines)["product_line_id"] == "FALL").sum()
    assert fall(modified) / fall(base_order_lines) == pytest.approx(0.70, abs=0.03)
    assert len(modified) == len(base_order_lines)


def test_intercompany_push_only_touches_its_flow(base_order_lines):
    effect = {"scope": {"entity_id": "FR", "customer_id": "C000"}, "start_date": "2026-01-01",
              "end_date": None, "shape": "step", "parameters": {"magnitude": 0.30}}
    modified = effects.apply_intercompany_push(base_order_lines, effect, np.random.default_rng(6))
    others = lambda lines: lines[lines["customer_id"] != "C000"]
    assert len(others(modified)) == len(others(base_order_lines))
    flow = lambda lines: after_start(lines, entity_id="FR")[lambda d: d["customer_id"] == "C000"]
    assert len(flow(modified)) / len(flow(base_order_lines)) == pytest.approx(1.30, abs=0.15)
