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
                        "list_unit_price_amount_local": 10.0,
                        "discount_rate": 0.10,
                        "net_unit_price_amount_local": 9.0,
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


PRICE_DROP = {"scope": {"entity_id": "DE"}, "start_date": "2026-01-01", "end_date": None,
              "shape": "step", "parameters": {"net_price_change": -0.05}}


def test_discount_mechanism_raises_discount_not_list_price(base_order_lines):
    effect = {**PRICE_DROP, "parameters": {**PRICE_DROP["parameters"], "mechanism": "discount"}}
    modified = effects.apply_price_change(base_order_lines, effect, np.random.default_rng(7))
    germany = after_start(modified)
    assert (germany["list_unit_price_amount_local"] == 10.0).all()
    assert germany["discount_rate"].iloc[0] == pytest.approx(0.145)
    assert germany["net_unit_price_amount_local"].iloc[0] == pytest.approx(8.55)


def test_list_price_mechanism_lowers_list_price_not_discount(base_order_lines):
    effect = {**PRICE_DROP, "parameters": {**PRICE_DROP["parameters"], "mechanism": "list_price"}}
    modified = effects.apply_price_change(base_order_lines, effect, np.random.default_rng(7))
    germany = after_start(modified)
    assert (germany["discount_rate"] == 0.10).all()
    assert germany["list_unit_price_amount_local"].iloc[0] == pytest.approx(9.50)
    assert germany["net_unit_price_amount_local"].iloc[0] == pytest.approx(8.55)


def test_price_change_keeps_volumes_and_other_entities(base_order_lines):
    effect = {**PRICE_DROP, "parameters": {**PRICE_DROP["parameters"], "mechanism": "discount"}}
    modified = effects.apply_price_change(base_order_lines, effect, np.random.default_rng(7))
    assert modified["quantity"].sum() == base_order_lines["quantity"].sum()
    france = modified[modified["entity_id"] == "FR"]
    assert (france["net_unit_price_amount_local"] == 9.0).all()


@pytest.fixture
def monthly_costs():
    """Coût groupe mensuel de 2 articles sur 2 ans : 4,00 € chacun."""
    months = pd.date_range("2025-01-01", "2026-12-01", freq="MS")
    return pd.DataFrame(
        [{"product_id": p, "product_line_id": line, "month_start_date": m, "unit_cost_amount_eur": 4.0}
         for p, line in (("HAND-001", "HAND"), ("FOOT-001", "FOOT")) for m in months]
    )


def test_cost_change_raises_cost_from_start_date_only(monthly_costs):
    effect = {"scope": {"product_line_id": "HAND"}, "start_date": "2026-01-01", "end_date": None,
              "shape": "step", "parameters": {"cost_change": 0.08}}
    modified = effects.apply_cost_change(monthly_costs, effect, np.random.default_rng(8))
    hand = modified[modified["product_line_id"] == "HAND"].set_index("month_start_date")
    assert hand.loc["2025-12-01", "unit_cost_amount_eur"] == 4.0
    assert hand.loc["2026-01-01", "unit_cost_amount_eur"] == pytest.approx(4.32)
    assert (modified[modified["product_line_id"] == "FOOT"]["unit_cost_amount_eur"] == 4.0).all()


@pytest.fixture
def base_shipments():
    """2 000 lignes de commande en 2026, en France et en Allemagne.

    Chacune est promise 10 jours après la commande et expédiée à l'heure,
    entre 3 et 10 jours après la commande, en une seule fois.
    """
    rng = np.random.default_rng(seed=10)
    order_dates = pd.Timestamp("2026-01-01") + pd.to_timedelta(rng.integers(0, 330, 2000), unit="D")
    promised = order_dates + pd.Timedelta(days=10)
    return pd.DataFrame({
        "order_number": [f"O{i:05d}" for i in range(2000)],
        "order_line_number": 1,
        "entity_id": np.where(np.arange(2000) < 1000, "FR", "DE"),
        "warehouse_id": np.where(np.arange(2000) < 1000, "FR-APT", "DE-DEP"),
        "order_date": order_dates,
        "first_promised_date": promised,
        "promised_date": promised,
        "shipped_date": order_dates + pd.to_timedelta(rng.integers(3, 11, 2000), unit="D"),
        "shipped_quantity": rng.integers(10, 101, 2000),
    })


DELAY = {"scope": {"entity_id": "DE"}, "start_date": "2026-01-01", "end_date": None, "shape": "step",
         "parameters": {"late_share": 0.20, "average_delay_days": 6, "reschedule_share": 0.5,
                        "partial_share": 0.10, "cancellation_share": 0.3}}


def otif_rates(lines, promise_column):
    """OTIF par ligne de commande : tout expédié au plus tard à la promesse."""
    on_time_quantity = lines["shipped_quantity"].where(lines["shipped_date"] <= lines[promise_column], 0)
    per_line = lines.assign(on_time=on_time_quantity).groupby("order_number").agg(
        on_time=("on_time", "sum"), shipped=("shipped_quantity", "sum"),
        cancelled=("cancelled_quantity", "sum"))
    return (per_line["on_time"] >= per_line["shipped"] + per_line["cancelled"]).mean()


def test_delay_keeps_quantities_and_first_promise(base_shipments):
    modified = effects.apply_fulfilment_delay(base_shipments, DELAY, np.random.default_rng(11))
    total = modified["shipped_quantity"].sum() + modified["cancelled_quantity"].sum()
    assert total == base_shipments["shipped_quantity"].sum()
    first = modified.drop_duplicates("order_number").set_index("order_number")["first_promised_date"]
    assert first.equals(base_shipments.set_index("order_number")["first_promised_date"])


def test_delay_hits_official_otif_harder_than_comparable(base_shipments):
    modified = effects.apply_fulfilment_delay(base_shipments, DELAY, np.random.default_rng(11))
    germany = modified[modified["entity_id"] == "DE"]
    official = otif_rates(germany, "first_promised_date")
    comparable = otif_rates(germany, "promised_date")
    assert official == pytest.approx(0.72, abs=0.04)
    assert comparable > official + 0.05


def test_delay_leaves_france_on_time(base_shipments):
    modified = effects.apply_fulfilment_delay(base_shipments, DELAY, np.random.default_rng(11))
    france = modified[modified["entity_id"] == "FR"]
    assert otif_rates(france, "first_promised_date") == 1


def test_disruption_delays_shipments_then_catches_up(base_shipments):
    effect = {"scope": {"warehouse_id": "DE-DEP"}, "start_date": "2026-03-26", "end_date": "2026-04-07",
              "parameters": {"shipment_capacity": 0.40, "catch_up_weeks": 3}}
    modified = effects.apply_service_disruption(base_shipments, effect, np.random.default_rng(12))
    window = lambda lines: lines[(lines["warehouse_id"] == "DE-DEP")
                                 & lines["shipped_date"].between("2026-03-26", "2026-04-07")]
    assert len(window(modified)) / len(window(base_shipments)) == pytest.approx(0.40, abs=0.12)
    assert modified["shipped_quantity"].sum() == base_shipments["shipped_quantity"].sum()
    assert modified["shipped_date"].max() <= pd.Timestamp("2026-12-31")


@pytest.fixture
def monthly_receipts():
    """Réceptions mensuelles de 2 articles à Apt, sur 2 ans.

    Les deux reçoivent 1 000 unités par mois. À partir de janvier 2026, les
    ventes de HAND-001 baissent et la base réduit ses réceptions à 500 :
    c'est ce que ferait un approvisionneur attentif.
    """
    months = pd.date_range("2025-01-01", "2026-12-01", freq="MS")
    rows = []
    for product_id in ("HAND-001", "FOOT-001"):
        for month in months:
            adapted = product_id == "HAND-001" and month >= pd.Timestamp("2026-01-01")
            rows.append({"warehouse_id": "FR-APT", "product_id": product_id,
                         "month_start_date": month, "received_quantity": 500 if adapted else 1000})
    return pd.DataFrame(rows)


def test_frozen_replenishment_keeps_receiving_as_before(monthly_receipts):
    effect = {"scope": {"warehouse_id": "FR-APT", "product_id": "HAND-001"}, "start_date": "2026-01-01",
              "end_date": None, "shape": "step", "parameters": {"frozen_replenishment": True}}
    modified = effects.apply_dormant_stock(monthly_receipts, effect, np.random.default_rng(13))
    hand_2026 = modified[(modified["product_id"] == "HAND-001") & (modified["month_start_date"] >= "2026-01-01")]
    assert (hand_2026["received_quantity"] == 1000).all()


def test_excess_receipt_adds_months_of_stock_once(monthly_receipts):
    effect = {"scope": {"warehouse_id": "FR-APT", "product_id": "FOOT-001"}, "start_date": "2026-03-01",
              "end_date": None, "shape": "step", "parameters": {"excess_receipt_months": 6}}
    modified = effects.apply_dormant_stock(monthly_receipts, effect, np.random.default_rng(13))
    foot = modified[modified["product_id"] == "FOOT-001"].set_index("month_start_date")["received_quantity"]
    assert foot.loc["2026-03-01"] == 7000
    assert foot.loc["2026-04-01"] == 1000
    assert foot.sum() == monthly_receipts.loc[monthly_receipts["product_id"] == "FOOT-001", "received_quantity"].sum() + 6000


def test_dormant_stock_leaves_other_articles_untouched(monthly_receipts):
    effect = {"scope": {"warehouse_id": "FR-APT", "product_id": "HAND-001"}, "start_date": "2026-01-01",
              "end_date": None, "shape": "step",
              "parameters": {"frozen_replenishment": True, "excess_receipt_months": 3}}
    modified = effects.apply_dormant_stock(monthly_receipts, effect, np.random.default_rng(13))
    other = lambda r: r[r["product_id"] == "FOOT-001"]["received_quantity"].tolist()
    assert other(modified) == other(monthly_receipts)


@pytest.fixture
def brazil_flows():
    """Ventes du Brésil à ses clients et ventes de Shanghai au Brésil, en 2026.

    Le Brésil vend 400 lignes par mois, dont 20 % de produits du groupe.
    Shanghai lui vend 400 lignes par mois de produits du groupe.
    """
    rng = np.random.default_rng(seed=20)
    rows = []
    for month in pd.date_range("2026-01-01", "2026-12-01", freq="MS"):
        for i in range(400):
            rows.append({"order_number": f"BR-{month:%m}-{i}", "entity_id": "BR", "customer_id": f"C{i % 50}",
                         "order_date": month + pd.Timedelta(days=int(rng.integers(0, 28))), "quantity": 10,
                         "product_type": "group" if rng.random() < 0.2 else "local"})
            rows.append({"order_number": f"CN-{month:%m}-{i}", "entity_id": "CN", "customer_id": "BR",
                         "order_date": month + pd.Timedelta(days=int(rng.integers(0, 28))), "quantity": 10,
                         "product_type": "group"})
    return pd.DataFrame(rows)


def test_derived_purchases_follow_realized_sales_two_months_ahead(brazil_flows):
    integration = {"scope": {"entity_id": "BR"}, "start_date": "2026-01-01", "end_date": None,
                   "shape": "ramp", "ramp_months": 11,
                   "parameters": {"target_products": {"product_type": "group"},
                                  "share_start": 0.20, "share_end": 0.35}}
    after_integration = effects.apply_product_mix_shift(brazil_flows, integration, np.random.default_rng(21))
    sales_change = effects.realized_monthly_change(
        brazil_flows, after_integration, {"entity_id": "BR", "product_type": "group"})

    purchases = {"scope": {"entity_id": "CN", "customer_id": "BR"}, "start_date": "2026-01-01",
                 "end_date": None, "lag_months": -2}
    result = effects.apply_derived_volume_change(after_integration, purchases, sales_change,
                                                 np.random.default_rng(22))
    purchase_change = effects.realized_monthly_change(
        after_integration, result, {"entity_id": "CN", "customer_id": "BR"})

    october, december = pd.Period("2026-10", "M"), pd.Period("2026-12", "M")
    assert sales_change[december] > 0.5
    assert purchase_change[october] == pytest.approx(sales_change[december], abs=0.1)
