-- =====================================================================
-- Thème 1 – Jointures et grain
-- Question 1.3 – L'OTIF
-- =====================================================================
-- Énoncé : ajouter is_otif à la requête 1.2 : vrai si la ligne est
--   entièrement expédiée au plus tard à sa première date promise ; faux
--   sinon ; NULL si la première date promise est après la date de
--   référence. Puis calculer l'OTIF des lignes promises en septembre 2026
--   (lignes OTIF / lignes promises dans le mois).
--   « Entièrement » = la quantité expédiée au plus tard à la première
--   date promise atteint la quantité commandée (une quantité annulée
--   compte comme non livrée).
-- Tables : sql_practice.order_lines, sql_practice.deliveries
-- Date de référence : 2026-09-30
-- ---------------------------------------------------------------------
-- Grain du résultat : une seule ligne, le taux OTIF de septembre 2026.
--   Étape intermédiaire (order_line_with_otif_status) : une ligne = une
--   ligne de commande (12 lignes), avec is_otif.
--
-- Prédiction de contrôle (avant d'exécuter) :
--   1. Lignes promises en septembre : 10 (DE 46012/1 et FR 46020/1 sont
--      promises en octobre : is_otif = NULL, hors du calcul).
--   2. Lignes OTIF : 5.
--      - TRUE : DE 45872/1, DE 45990/1, FR 45872/1, FR 45901/1,
--        FR 45901/2 (fractionnée, mais les deux expéditions sont parties
--        au plus tard le 12/09, date promise).
--      - FALSE :
--        FR 45872/2 : fractionnée, dernière expédition le 16/09 pour
--          une promesse au 10/09 (en retard) ;
--        FR 45933/1 : expédiée le 22/09 pour le 18/09 (en retard) ;
--        FR 45940/1 : jamais expédiée (promesse passée, rien de livré) ;
--        FR 45940/2 : 60 expédiées sur 80 commandées, 20 annulées
--          (incomplète : l'annulation compte comme non livrée) ;
--        DE 45990/2 : 10 expédiées sur 15 (incomplète).
--   3. Taux : 5 / 10 = 0,5.
--
-- Raisonnement :
--   - is_otif se calcule sur la ligne de commande, pas sur l'expédition :
--     une ligne jamais expédiée doit rester dans le calcul, c'est le pire
--     échec. On repart donc de la requête 1.2 (une ligne par ligne de
--     commande).
--   - À l'heure : la dernière expédition est au plus tard à la première
--     date promise. Si la dernière est à l'heure, toutes les autres aussi.
--   - En totalité : la quantité expédiée atteint la quantité commandée
--     (>= plutôt que =, pour ne pas pénaliser une livraison en trop).
--   - Annulation : faute de motif d'annulation, règle prudente, la
--     quantité annulée compte comme non livrée.
--   - Ordre des tests dans le CASE : d'abord la promesse future (NULL),
--     car on ne peut pas encore juger ; ensuite les conditions de succès.
--   - Ligne jamais expédiée : last_shipped_date est NULL, la comparaison
--     vaut NULL, le CASE passe au ELSE : FALSE.
--   - Taux : numérateur = lignes OTIF, dénominateur = lignes promises en
--     septembre. Le filtre is_otif IS NOT NULL ne change rien pour
--     septembre (toutes les promesses sont passées) : il protège le calcul
--     d'un mois en cours, où une partie des lignes n'est pas jugeable.
--   - Taux entre 0 et 1 : l'affichage en % se fait dans Power BI.
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
),

order_line_with_otif_status AS (
    SELECT
        ol.entity_id,
        ol.order_number,
        ol.order_line_number,
        ol.first_promised_date,
        spol.last_shipped_date,
        COALESCE(spol.shipped_quantity, 0)       AS shipped_quantity,
        COALESCE(spol.shipment_count, 0)         AS shipment_count,
        ol.ordered_quantity
            - ol.cancelled_quantity
            - COALESCE(spol.shipped_quantity, 0) AS open_quantity,
        CASE
            WHEN ol.first_promised_date > p.reference_date THEN NULL
            WHEN spol.last_shipped_date <= ol.first_promised_date
                AND COALESCE(spol.shipped_quantity, 0) >= ol.ordered_quantity THEN TRUE
            ELSE FALSE
        END                                      AS is_otif
    FROM sql_practice.order_lines AS ol
    LEFT JOIN shipments_per_order_line AS spol
        ON  ol.entity_id         = spol.entity_id
        AND ol.order_number      = spol.order_number
        AND ol.order_line_number = spol.order_line_number
    CROSS JOIN parameters AS p
)

SELECT
    SAFE_DIVIDE(COUNTIF(olos.is_otif), COUNT(*)) AS otif_rate
FROM order_line_with_otif_status AS olos
WHERE olos.is_otif IS NOT NULL
    AND DATE_TRUNC(olos.first_promised_date, MONTH) = DATE '2026-09-01'

-- ---------------------------------------------------------------------
-- Résultat obtenu : otif_rate = 0.5. Contrôle ligne par ligne fait avec
--   SELECT * FROM order_line_with_otif_status : 12 lignes, is_otif
--   conforme à la prédiction (5 TRUE, 5 FALSE, 2 NULL).
-- Écart avec la prédiction : aucun.
--
-- Ce que je retiens :
--   - L'OTIF se rattache aux lignes de commande, et le dénominateur, ce
--     sont les lignes promises dans la période, pas celles expédiées.
--   - NULL = pas encore jugeable ; FALSE = promesse non tenue. Une ligne
--     jamais expédiée dont la promesse est passée est FALSE.
--   - Dans un CASE, l'ordre des WHEN compte : le premier vrai l'emporte.
--   - Une même colonne se traite selon la question : l'annulation est
--     retirée du reste à livrer, mais compte comme non livrée pour l'OTIF.
--   - Une CTE garde les colonnes utiles aux étapes suivantes (ici
--     first_promised_date pour le filtre) ; le résultat final ne renvoie
--     que ce qui est demandé.
