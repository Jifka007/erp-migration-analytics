-- =====================================================================
-- Thème 1 – Jointures et grain
-- Question 1.2 – Une ligne par ligne de commande
-- =====================================================================
-- Énoncé : renvoyer exactement une ligne par ligne de commande (12 lignes),
--   situation au 30 septembre 2026, avec la date de la dernière expédition,
--   la quantité totale expédiée, le nombre d'expéditions et la quantité
--   restant à livrer (commandée − annulée − expédiée). Les lignes jamais
--   expédiées apparaissent, avec une quantité expédiée et un nombre
--   d'expéditions à 0.
-- Tables : sql_practice.order_lines, sql_practice.deliveries
-- Date de référence : 2026-09-30
-- ---------------------------------------------------------------------
-- Grain du résultat : une ligne = une ligne de commande (12 lignes).
--
-- Prédiction de contrôle (avant d'exécuter) :
--   1. Nombre de lignes : 12, une par ligne de commande (grain de
--      order_lines conservé grâce à l'agrégation avant la jointure).
--   2. Totaux de contrôle :
--      - SUM(shipped_quantity) = 630, soit le total de shipped_quantity
--        dans deliveries (toutes les expéditions sont antérieures au
--        30 septembre, aucune n'est perdue ni comptée deux fois) ;
--      - SUM(shipment_count) = 11, soit le nombre de lignes de
--        deliveries.
--   3. Cas limites :
--      - FR 45872/2, expédiée en deux fois : last_shipped_date =
--        2026-09-16, shipped_quantity = 20, shipment_count = 2,
--        open_quantity = 0 ;
--      - FR 45940/1, jamais expédiée : last_shipped_date = NULL,
--        shipped_quantity = 0, shipment_count = 0, open_quantity = 10 ;
--      - FR 45940/2, reliquat annulé : 80 commandées − 20 annulées
--        − 60 expédiées, donc open_quantity = 0.
--
-- Raisonnement :
--   - deliveries est plus fine que order_lines (0, 1 ou plusieurs
--     expéditions par ligne). Joindre directement donnerait 14 lignes
--     (question 1.1). On agrège donc deliveries par ligne de commande
--     AVANT de joindre : une ligne par ligne de commande de chaque côté,
--     et le LEFT JOIN garde les 12 lignes.
--   - Le filtre de date (<= 30 septembre) est dans la CTE : placé dans le
--     WHERE final, il supprimerait les lignes jamais expédiées, dont la
--     date vaut NULL après le LEFT JOIN.
--   - Ligne jamais expédiée : quantité et nombre à 0 (COALESCE), car
--     l'absence d'expédition vaut zéro. La dernière date reste NULL : il
--     n'y a pas de date, et en inventer une ferait croire à une
--     expédition.
--   - Reste à livrer : la quantité annulée est retirée, car plus personne
--     ne l'attend (FR 45940/2 : 80 − 20 − 60 = 0).
-- ---------------------------------------------------------------------

WITH parameters AS (
    SELECT
        DATE '2026-09-30' AS reference_date
),

shipments_per_order_line AS (
    SELECT
        d.entity_id,
        d.order_number,
        d.order_line_number,
        MAX(d.shipped_date)     AS last_shipped_date,
        SUM(d.shipped_quantity) AS shipped_quantity,
        COUNT(*)                AS shipment_count
    FROM sql_practice.deliveries AS d
    CROSS JOIN parameters AS p
    WHERE d.shipped_date <= p.reference_date
    GROUP BY
        d.entity_id,
        d.order_number,
        d.order_line_number
)

SELECT
    ol.entity_id,
    ol.order_number,
    ol.order_line_number,
    spol.last_shipped_date,
    COALESCE(spol.shipped_quantity, 0)       AS shipped_quantity,
    COALESCE(spol.shipment_count, 0)         AS shipment_count,
    ol.ordered_quantity
        - ol.cancelled_quantity
        - COALESCE(spol.shipped_quantity, 0) AS open_quantity
FROM sql_practice.order_lines AS ol
LEFT JOIN shipments_per_order_line AS spol
    ON  ol.entity_id         = spol.entity_id
    AND ol.order_number      = spol.order_number
    AND ol.order_line_number = spol.order_line_number
ORDER BY
    ol.entity_id,
    ol.order_number,
    ol.order_line_number

-- ---------------------------------------------------------------------
-- Résultat obtenu : 12 lignes ; SUM(shipped_quantity) = 630 et
--   SUM(shipment_count) = 11 ; les trois cas limites sont conformes.
-- Écart avec la prédiction : aucun.
--
-- Ce que je retiens :
--   - Quand la table de droite est plus fine que celle de gauche, on
--     l'agrège à la clé de gauche avant de joindre (sinon fan-out).
--   - Un filtre sur la table de droite d'un LEFT JOIN va dans la CTE ou
--     le ON, jamais dans le WHERE final.
--   - Dans un LEFT JOIN, une condition sur la table de gauche placée dans
--     le ON ne filtre rien : elle empêche seulement les correspondances.
--   - COALESCE à 0 quand l'absence vaut zéro (une quantité) ; NULL gardé
--     quand la valeur n'existe pas (une date).
--   - Extension pour le projet : ce calcul est le cœur de fct_order_lines.
