-- =====================================================================
-- Thème 1 – Jointures et grain
-- Question 1.1 – Compter avant de joindre
-- =====================================================================
-- Énoncé : combien de lignes dans order_lines et dans deliveries ?
--   Avant d'exécuter, prédire le nombre de lignes d'un LEFT JOIN de
--   order_lines vers deliveries sur la clé complète de la ligne de
--   commande (entity_id, order_number, order_line_number), puis vérifier.
--   Expliquer pourquoi le résultat n'est ni 12 ni 11.
-- Tables : sql_practice.order_lines, sql_practice.deliveries
-- Date de référence : 2026-09-30
-- ---------------------------------------------------------------------
-- Grain du résultat : une seule ligne, qui contient les trois comptages.
-- Grain de la jointure : une ligne = une ligne de commande associée à
--   une de ses expéditions. Une ligne de commande jamais expédiée
--   apparaît une fois, avec les colonnes de deliveries à NULL.
--
-- Prédiction (avant d'exécuter) :
--   entity_id | order_number | order_line_number | matching_deliveries
--   DE        | 45872        | 1                 | 1
--   DE        | 45990        | 1                 | 1
--   DE        | 45990        | 2                 | 1
--   DE        | 46012        | 1                 | 0
--   FR        | 45872        | 1                 | 1
--   FR        | 45872        | 2                 | 2
--   FR        | 45901        | 1                 | 1
--   FR        | 45901        | 2                 | 2
--   FR        | 45933        | 1                 | 1
--   FR        | 45940        | 1                 | 0
--   FR        | 45940        | 2                 | 1
--   FR        | 46020        | 1                 | 0
--   3 lignes à 0 expédition (3 lignes) + 7 lignes à 1 (7 lignes)
--   + 2 lignes à 2 (4 lignes) = 14 lignes.
--
-- Raisonnement : un LEFT JOIN garde chaque ligne de gauche au moins une
--   fois, et la répète autant de fois qu'elle trouve de correspondances
--   à droite. Donc :
--   nombre de lignes = lignes de gauche sans correspondance
--                    + correspondances trouvées
--                    = 3 + 11 = 14.
-- ---------------------------------------------------------------------

WITH order_line_totals AS (
    SELECT
        COUNT(*) AS order_line_count
    FROM sql_practice.order_lines AS ol
),

delivery_totals AS (
    SELECT
        COUNT(*) AS delivery_count
    FROM sql_practice.deliveries AS d
),

joined_row_totals AS (
    SELECT
        COUNT(*) AS joined_row_count
    FROM sql_practice.order_lines AS ol
    LEFT JOIN sql_practice.deliveries AS d
        ON  ol.entity_id         = d.entity_id
        AND ol.order_number      = d.order_number
        AND ol.order_line_number = d.order_line_number
)

SELECT
    olt.order_line_count,
    dt.delivery_count,
    jrt.joined_row_count
FROM order_line_totals AS olt
CROSS JOIN delivery_totals AS dt
CROSS JOIN joined_row_totals AS jrt

-- ---------------------------------------------------------------------
-- Résultat obtenu : order_line_count = 12, delivery_count = 11,
--   joined_row_count = 14.
-- Écart avec la prédiction : aucun.
--
-- Pourquoi ni 12 ni 11 :
--   - pas 12 : les deux lignes expédiées en deux fois (FR 45872/2 et
--     FR 45901/2) apparaissent chacune deux fois, soit 12 + 2 = 14 ;
--   - pas 11 : les trois lignes jamais expédiées (DE 46012/1,
--     FR 45940/1, FR 46020/1) sont gardées par le LEFT JOIN,
--     soit 11 + 3 = 14.
--
-- Une expédition sans ligne de commande serait perdue : le LEFT JOIN ne
--   garde que les lignes de gauche. Pour la repérer, il faut partir de
--   deliveries. C'est un contrôle de qualité (thème 10).
--
-- Ce que je retiens : avant de joindre, je compte les lignes de chaque
--   table et je prédis le résultat. Un LEFT JOIN ne garde pas le nombre
--   de lignes de gauche : il en donne au moins autant, plus une ligne
--   par correspondance supplémentaire.
