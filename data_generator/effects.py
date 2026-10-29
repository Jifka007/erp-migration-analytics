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
