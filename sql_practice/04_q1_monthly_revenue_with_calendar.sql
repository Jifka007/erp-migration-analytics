-- =====================================================================
-- Thème 4 – Dates et fenêtres glissantes
-- Question 4.1 – Le CA mensuel, mois vides compris
-- =====================================================================
-- Énoncé : pour chaque filiale et chaque mois de janvier à septembre 2026,
--   le nombre de factures et le CA. Un mois sans facture doit apparaître,
--   avec 0. Vérifier que le total des 18 lignes égale le CA de 2026 lu
--   directement dans customer_invoices.
-- Tables : sql_practice.customer_invoices, sql_practice.entities
-- Date de référence : 2026-09-30 (fin de journée)
-- ---------------------------------------------------------------------
-- Grain du résultat : une ligne = une filiale (le contrôle).
--   Étapes :
--     - parameters : une ligne, les deux bornes de la période ;
--     - months : une ligne = un mois de la période (9) ;
--     - entity_months : une ligne = une filiale et un mois (18), le
--       squelette ;
--     - monthly_invoices : une ligne = une filiale et un mois avec au
--       moins une facture (8) ;
--     - monthly_revenue : une ligne = une filiale et un mois (18), mois
--       vides à 0 : c'est le résultat demandé ;
--     - entity_revenue_from_calendar et entity_revenue_direct : une ligne
--       = une filiale (2).
--
-- Prédiction de contrôle (avant d'exécuter) :
--   1. Nombre de lignes : 18 dans monthly_revenue, dont 10 à zéro ;
--      2 dans le résultat final.
--   2. Totaux de contrôle :
--      - FR : février 950, mars 700 (F-0107 400 + F-0108 300),
--        juillet 1100, septembre 500 ; total 3250 ;
--        mois vides : janvier, avril, mai, juin, août ;
--      - DE : janvier 1300, mai 1250, juin 700, août 650 ; total 3900 ;
--        mois vides : février, mars, avril, juillet, septembre ;
--      - total 7150 ; écart de contrôle 0 pour les deux filiales.
--   3. Cas limites :
--      - FR en mars : 2 factures, invoice_count = 2 ;
--      - F-0110 du 2026-09-30 : dernier jour de la période, incluse
--        (BETWEEN inclut les bornes) ;
--      - factures de 2024 et 2025 : écartées par le filtre de dates.
--
-- Raisonnement :
--   - Un GROUP BY sur les factures ne produit que les mois où il y a des
--     factures : un mois vide n'existe pas. Il faut un squelette qui
--     contient tous les mois, indépendant des factures.
--   - GENERATE_DATE_ARRAY renvoie une liste (ARRAY) dans une seule
--     cellule ; UNNEST la déplie en lignes. UNNEST peut lire les colonnes
--     d'une table placée avant lui dans le FROM (ici parameters).
--   - Chaque mois pour chaque filiale : CROSS JOIN (pas de clé commune,
--     toutes les combinaisons, 2 × 9 = 18). Un FULL OUTER JOIN demande
--     une condition ON, et un mois n'est égal à aucune filiale.
--   - Les factures sont agrégées par filiale et mois AVANT la jointure :
--     la jointure se fait ensuite sur des égalités simples, et la CTE
--     agrégée est réutilisable.
--   - LEFT JOIN depuis le squelette : un mois sans facture reste, avec
--     des NULL, remplacés par 0 (COALESCE) : l'absence de vente vaut 0.
--   - Les bornes de la période sont écrites une seule fois (parameters) :
--     le calendrier, les filtres et le contrôle en dépendent. Pour une
--     autre période, on ne change que deux dates.
--   - Le filtre de dates dans monthly_invoices évite de lire tout
--     l'historique (BigQuery facture les données lues). BETWEEN convient
--     pour une colonne DATE ; avec un TIMESTAMP, on écrirait
--     < période + 1 jour.
--   - Contrôle : le CA recalculé directement dans customer_invoices,
--     sans calendrier ni jointure, doit égaler la somme des 18 lignes.
--     Deux calculs indépendants, un écart arrondi.
-- ---------------------------------------------------------------------

WITH parameters AS (
    SELECT
        DATE '2026-01-01' AS period_start_date,
        DATE '2026-09-30' AS period_end_date
),

months AS (
    SELECT
        month_start_date
    FROM parameters AS p
    CROSS JOIN UNNEST(GENERATE_DATE_ARRAY(p.period_start_date, DATE_TRUNC(p.period_end_date, MONTH), INTERVAL 1 MONTH)) AS month_start_date
),

entity_months AS (
    SELECT
        e.entity_id,
        m.month_start_date
    FROM sql_practice.entities AS e
    CROSS JOIN months AS m
),

monthly_invoices AS (
    SELECT
        ci.entity_id,
        DATE_TRUNC(ci.invoice_date, MONTH) AS month_start_date,
        COUNT(*)                           AS invoice_count,
        SUM(ci.net_amount_eur)             AS revenue_amount_eur
    FROM sql_practice.customer_invoices AS ci
    CROSS JOIN parameters AS p
    WHERE ci.invoice_date BETWEEN p.period_start_date AND p.period_end_date
    GROUP BY
        ci.entity_id,
        DATE_TRUNC(ci.invoice_date, MONTH)
),

monthly_revenue AS (
    SELECT
        em.entity_id,
        em.month_start_date,
        COALESCE(mi.invoice_count, 0)      AS invoice_count,
        COALESCE(mi.revenue_amount_eur, 0) AS revenue_amount_eur
    FROM entity_months AS em
    LEFT JOIN monthly_invoices AS mi
        ON  em.entity_id        = mi.entity_id
        AND em.month_start_date = mi.month_start_date
),

entity_revenue_from_calendar AS (
    SELECT
        mr.entity_id,
        SUM(mr.revenue_amount_eur) AS revenue_amount_eur
    FROM monthly_revenue AS mr
    GROUP BY
        mr.entity_id
),

entity_revenue_direct AS (
    SELECT
        ci.entity_id,
        SUM(ci.net_amount_eur) AS revenue_amount_eur
    FROM sql_practice.customer_invoices AS ci
    CROSS JOIN parameters AS p
    WHERE ci.invoice_date BETWEEN p.period_start_date AND p.period_end_date
    GROUP BY
        ci.entity_id
)

-- Résultat demandé : SELECT * FROM monthly_revenue
--   ORDER BY entity_id, month_start_date (18 lignes).
-- Contrôle : une ligne par filiale, écart attendu 0.
SELECT
    erc.entity_id,
    erc.revenue_amount_eur                                      AS calendar_revenue_amount_eur,
    erd.revenue_amount_eur                                      AS direct_revenue_amount_eur,
    ROUND(erc.revenue_amount_eur - erd.revenue_amount_eur, 2)   AS control_gap_amount_eur
FROM entity_revenue_from_calendar AS erc
LEFT JOIN entity_revenue_direct AS erd
    ON  erc.entity_id = erd.entity_id
ORDER BY
    erc.entity_id

-- ---------------------------------------------------------------------
-- Résultat obtenu : monthly_revenue conforme à la prédiction (18 lignes,
--   10 à zéro) ; contrôle FR 3250 / 3250 / 0, DE 3900 / 3900 / 0.
-- Écart avec la prédiction : aucun.
--
-- Version courte (dbt, entretien) : avec un modèle calendrier dim_month
--   et dim_entity, le squelette devient FROM dim_entity CROSS JOIN
--   dim_month, puis LEFT JOIN des factures et GROUP BY ; le contrôle
--   devient un test dbt, hors du modèle.
--
-- Ce que je retiens :
--   - Un mois sans activité n'existe pas dans les données : on fabrique
--     un squelette (calendrier × filiales) et on y accroche les faits par
--     LEFT JOIN, avec COALESCE à 0.
--   - GENERATE_DATE_ARRAY fabrique une liste, UNNEST la transforme en
--     lignes.
--   - CROSS JOIN pour toutes les combinaisons de deux listes sans clé
--     commune.
--   - Agréger les factures au grain du squelette avant de joindre :
--     jointure sur des égalités simples, CTE réutilisable.
--   - Une CTE parameters pour les bornes de la période : écrites une
--     seule fois, tout le reste en dépend.
--   - Filtrer la période au plus tôt : BigQuery facture ce qu'il lit.
--   - COUNT(clé) ou COUNT(*) après agrégation, pas COUNTIF sur une colonne
--     hors clé ; COALESCE(SUM(x), 0) plutôt que SUM(COALESCE(x, 0)).
