"""Tests du moteur des effets, sur une petite base fabriquée (jamais le scénario réel)."""

import numpy as np
import pandas as pd
import pytest

from data_generator import effects


@pytest.fixture
def base_order_lines():
    """300 clients (150 en France, 150 en Allemagne), 2 ans de commandes.

    Chaque client commande en moyenne 3 fois par mois (loi de Poisson),
    des quantités entre 10 et 100.
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
