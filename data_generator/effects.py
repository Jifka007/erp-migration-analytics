"""Moteur des effets (tâche 1.6).

Chaque type d'effet du catalogue (config/delta_plus/effect_types.yml) est
une fonction qui reçoit la table des lignes de commande et un effet du
scénario, et renvoie la table modifiée. Les fonctions ne touchent qu'aux
lignes du périmètre (scope) et de la période de l'effet.
"""

import numpy as np
import pandas as pd


def scope_mask(order_lines: pd.DataFrame, effect: dict) -> pd.Series:
    """Lignes concernées par l'effet : dans son périmètre et dans sa période."""
    mask = order_lines["order_date"] >= pd.Timestamp(effect["start_date"])
    if effect.get("end_date"):
        mask &= order_lines["order_date"] <= pd.Timestamp(effect["end_date"])
    for column, value in effect["scope"].items():
        mask &= order_lines[column] == value
    return mask


def effect_strength(dates: pd.Series, effect: dict) -> pd.Series:
    """Part de l'ampleur finale atteinte à chaque date (entre 0 et 1).

    step : 1 dès le début de l'effet.
    ramp : monte régulièrement jusqu'à 1 en ramp_months mois.
    """
    if effect.get("shape", "step") == "step":
        return pd.Series(1.0, index=dates.index)
    start = pd.Timestamp(effect["start_date"])
    months_elapsed = (dates - start).dt.days / 30.44
    return (months_elapsed / effect["ramp_months"]).clip(0, 1)


def apply_volume_change(
    order_lines: pd.DataFrame, effect: dict, rng: np.random.Generator
) -> pd.DataFrame:
    """Les clients du périmètre commandent plus ou moins souvent.

    Baisse : des lignes sont retirées au hasard, mais jamais la dernière
    ligne d'un client sur la période, pour ne pas créer de clients perdus
    (ce serait la trace d'un autre effet, customer_attrition).
    Hausse : des lignes du périmètre sont dupliquées, comme des commandes
    supplémentaires.
    """
    in_scope = scope_mask(order_lines, effect)
    magnitude = effect["parameters"]["magnitude"]
    strength = effect_strength(order_lines["order_date"], effect)
    probability = (abs(magnitude) * strength).where(in_scope, 0.0)
    selected = pd.Series(rng.random(len(order_lines)) < probability, index=order_lines.index)

    if magnitude < 0:
        # On protège une ligne par client du périmètre : sa dernière commande.
        last_line_per_customer = (
            order_lines[in_scope]
            .sort_values("order_date")
            .groupby("customer_id")
            .tail(1)
            .index
        )
        selected[last_line_per_customer] = False
        return order_lines[~selected].copy()

    extra_lines = order_lines[selected].copy()
    extra_lines["order_number"] = extra_lines["order_number"].astype(str) + "-X"
    return pd.concat([order_lines, extra_lines], ignore_index=True)


def signal_to_noise(
    base: pd.DataFrame, modified: pd.DataFrame, effect: dict, freq: str = "QS"
) -> float:
    """L'effet ressort-il du bruit ? Rapport entre l'effet et le bruit.

    Signal : écart relatif moyen entre les volumes modifiés et les volumes
    de base, sur la période de l'effet, au niveau d'agrégation freq.
    Bruit : variation relative habituelle des volumes de base du périmètre
    avant l'effet, au même niveau d'agrégation.
    Un rapport d'au moins 3 signifie que l'effet ressort nettement.
    """
    def totals(lines: pd.DataFrame) -> pd.Series:
        scope_only = lines
        for column, value in effect["scope"].items():
            scope_only = scope_only[scope_only[column] == value]
        return scope_only.groupby(pd.Grouper(key="order_date", freq=freq))["quantity"].sum()

    start = pd.Timestamp(effect["start_date"])
    base_totals = totals(base)
    modified_totals = totals(modified)

    after = base_totals.index >= start
    signal = (modified_totals[after] / base_totals[after] - 1).mean()
    before = base_totals[~after]
    noise = before.std() / before.mean()
    return abs(signal) / noise


def apply_customer_attrition(
    order_lines: pd.DataFrame, effect: dict, rng: np.random.Generator
) -> pd.DataFrame:
    """Une part des clients du périmètre cesse de commander.

    Les clients perdus sont tirés au sort parmi ceux qui commandaient avant
    l'effet. Chacun part à une date : le début de l'effet (step) ou une
    date étalée sur la rampe (ramp). Toutes ses lignes après cette date
    disparaissent ; les autres clients ne changent pas.
    """
    start = pd.Timestamp(effect["start_date"])
    in_scope = scope_mask(order_lines, effect)
    customers = order_lines.loc[in_scope, "customer_id"].unique()

    lost_share = effect["parameters"]["lost_customer_share"]
    lost_customers = rng.choice(customers, size=round(lost_share * len(customers)), replace=False)

    if effect.get("shape", "step") == "ramp":
        offsets = rng.uniform(0, effect["ramp_months"] * 30.44, size=len(lost_customers))
        departure = {c: start + pd.Timedelta(days=d) for c, d in zip(lost_customers, offsets)}
    else:
        departure = {c: start for c in lost_customers}

    departure_dates = order_lines["customer_id"].map(departure)
    removed = in_scope & departure_dates.notna() & (order_lines["order_date"] >= departure_dates)
    return order_lines[~removed].copy()


def _replace_products(
    order_lines: pd.DataFrame,
    selected: pd.Series,
    donors: pd.DataFrame,
    rng: np.random.Generator,
    product_columns: list[str],
) -> pd.DataFrame:
    """Remplace le produit des lignes sélectionnées par celui de lignes donneuses.

    Seules les colonnes qui décrivent le produit changent : le client, la
    date et la quantité restent ceux de la ligne d'origine.
    """
    modified = order_lines.copy()
    columns = [c for c in product_columns if c in modified.columns]
    if selected.sum() == 0 or donors.empty:
        return modified
    picks = rng.integers(0, len(donors), size=int(selected.sum()))
    modified.loc[selected, columns] = donors[columns].iloc[picks].to_numpy()
    return modified


PRODUCT_COLUMNS = ["product_id", "product_type", "product_line_id", "product_family_id", "unit_price"]


def apply_product_mix_shift(
    order_lines: pd.DataFrame, effect: dict, rng: np.random.Generator
) -> pd.DataFrame:
    """La part d'un ensemble de produits change, sans changer le volume total.

    Exemple : la part des lignes en produits du groupe dans les ventes du
    Brésil passe de 20 % à 35 %. Des lignes de produits locaux deviennent des
    lignes de produits du groupe ; leur nombre et leurs quantités ne bougent pas.
    """
    params = effect["parameters"]
    in_scope = scope_mask(order_lines, effect)
    is_target = pd.Series(True, index=order_lines.index)
    for column, value in params["target_products"].items():
        is_target &= order_lines[column] == value

    base_share = is_target[in_scope].mean()
    strength = effect_strength(order_lines["order_date"], effect)
    wanted_share = params["share_start"] + (params["share_end"] - params["share_start"]) * strength

    if params["share_end"] >= base_share:
        # Des lignes hors cible deviennent des lignes de la cible.
        probability = ((wanted_share - base_share) / (1 - base_share)).clip(0, 1)
        candidates = in_scope & ~is_target
        donors = order_lines[in_scope & is_target]
    else:
        probability = ((base_share - wanted_share) / base_share).clip(0, 1)
        candidates = in_scope & is_target
        donors = order_lines[in_scope & ~is_target]

    selected = candidates & (rng.random(len(order_lines)) < probability)
    return _replace_products(order_lines, selected, donors, rng, PRODUCT_COLUMNS)


def apply_demand_transfer(
    order_lines: pd.DataFrame, effect: dict, rng: np.random.Generator
) -> pd.DataFrame:
    """Une partie de la demande passe d'un groupe de produits à un autre.

    Exemple : des clients délaissent une famille d'antichutes au profit d'un
    modèle plus récent. Le total ne change pas ; seul le produit change.
    """
    params = effect["parameters"]
    in_scope = scope_mask(order_lines, effect)

    def matches(product_scope: dict) -> pd.Series:
        mask = pd.Series(True, index=order_lines.index)
        for column, value in product_scope.items():
            mask &= order_lines[column] == value
        return mask

    from_lines = in_scope & matches(params["from_scope"])
    donors = order_lines[matches(params["to_scope"])]
    probability = params["transfer_share"] * effect_strength(order_lines["order_date"], effect)
    selected = from_lines & (rng.random(len(order_lines)) < probability)
    return _replace_products(order_lines, selected, donors, rng, PRODUCT_COLUMNS)


def apply_intercompany_push(
    order_lines: pd.DataFrame, effect: dict, rng: np.random.Generator
) -> pd.DataFrame:
    """Une plateforme envoie à une filiale plus qu'elle n'en revend.

    Le mécanisme est celui de volume_change, appliqué aux ventes internes
    (scope : la plateforme qui vend et la filiale cliente). C'est un type à
    part parce que son sens et ses traces diffèrent : il se lit en comparant
    les ventes internes aux ventes extérieures de la filiale.
    """
    return apply_volume_change(order_lines, effect, rng)
