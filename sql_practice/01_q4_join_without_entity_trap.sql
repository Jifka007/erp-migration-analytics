-- =====================================================================
-- Thème 1 – Jointures et grain
-- Question 1.4 – Le piège de la clé incomplète
-- =====================================================================
-- Énoncé : refaire le LEFT JOIN de la question 1.1 en oubliant entity_id
--   dans la condition de jointure. Prédire le nombre de lignes, vérifier,
--   puis dire quelles lignes de commande sont faussées et quelle serait la
--   conséquence sur l'OTIF.
-- Tables : sql_practice.order_lines, sql_practice.deliveries
-- Date de référence : 2026-09-30
-- ---------------------------------------------------------------------
-- Grain du résultat : une seule ligne, qui contient les trois comptages.
--   Grain de la jointure : une ligne = une ligne de commande associée à
--   une livraison qui a le même order_number et le même
--   order_line_number, quelle que soit sa filiale ; une ligne sans
--   livraison apparaît une fois, avec des NULL.
--
-- Prédiction (avant d'exécuter) :
--   - Avec la clé complète (question 1.1) : 14 lignes.
--   - Sans entity_id, seul un couple (order_number, order_line_number)
--     existe dans les deux filiales : 45872/1 (FR et DE). Chacune de ces
--     deux lignes trouve 2 livraisons au lieu d'une (L-901 et L-950).
--   - Total : 14 + 2 = 16 lignes.
--
-- Raisonnement : sans entity_id, le couple (order_number,
--   order_line_number) n'est plus une clé : les numéros de commande sont
--   propres à chaque filiale, et deux filiales peuvent avoir le même. Une
--   ligne de commande trouve alors aussi les livraisons de l'autre
--   filiale. Les lignes de gauche ne sont pas fusionnées (entity_id
--   reste dans order_lines) : chacune reçoit des livraisons en trop.
-- ---------------------------------------------------------------------

WITH order_line_totals AS (
    SELECT
        COUNT(*) AS order_line_count
    FROM sql_practice.order_lines
),

delivery_totals AS (
    SELECT
        COUNT(*) AS delivery_count
    FROM sql_practice.deliveries
),

joined_row_totals AS (
    SELECT
        COUNT(*) AS joined_row_count
    FROM sql_practice.order_lines AS ol
    LEFT JOIN sql_practice.deliveries AS d
        -- entity_id volontairement oublié (le piège étudié)
        ON  ol.order_number      = d.order_number
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
--   joined_row_count = 16.
-- Écart avec la prédiction : aucun.
--
-- Lignes faussées : FR 45872/1 et DE 45872/1. Chacune reçoit aussi la
--   livraison de l'autre filiale (L-901 et L-950), d'où 2 lignes de plus.
--
-- Conséquence sur l'OTIF (logique de la question 1.3) :
--   - FR 45872/1 : 220 pièces au lieu de 100, dernière expédition le
--     14/09 au lieu du 09/09, après sa promesse du 10/09 : FALSE au lieu
--     de TRUE ;
--   - DE 45872/1 : 220 pièces au lieu de 120, dernière expédition le
--     14/09, avant sa promesse du 15/09 : TRUE, mais par chance.
--   L'OTIF de septembre tombe de 0,5 à 0,4, et la quantité expédiée
--   totale de 630 à 850, sans aucun message d'erreur.
--
-- Ce que je retiens :
--   - Une clé de jointure contient toutes les colonnes qui rendent la
--     ligne unique. Dans un groupe multi-filiales, les numéros sont
--     propres à chaque filiale : entity_id fait partie de la clé.
--   - Une clé incomplète ne produit pas d'erreur : elle produit des
--     chiffres faux. Le contrôle du nombre de lignes après jointure
--     (16 au lieu des 14 attendues) suffit à la détecter.