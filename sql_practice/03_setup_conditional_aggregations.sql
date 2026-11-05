-- =====================================================================
-- Entraînement SQL, thème 3 : agrégations conditionnelles
-- Une nouvelle table, à l'image de fct_sales_lines (document 01), à côté
-- de products (thème 2). Montants en euros (la conversion est au thème 8).
-- À exécuter une seule fois dans la console BigQuery (région US).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Une ligne = une ligne de facture ou d'avoir (18 lignes)
--   - document_type : 'invoice' (facture) ou 'credit_note' (avoir)
--   - credit_note_type : 'return' (retour de marchandise) ou
--     'price_adjustment' (geste commercial, sans quantité) ; NULL pour
--     une facture
--   - les avoirs sont signés : quantité, montant et coût négatifs
--   - is_intercompany : vente à une autre filiale du groupe (clients IC-…)
--   - net_amount_eur = invoiced_quantity × list_unit_price_eur
--     × (1 − discount_rate)
--   - cost_amount_eur : coût de revient des marchandises vendues
--   - original_invoice_number, original_invoice_line_number : pour un
--     avoir, la facture (et la ligne) qu'il corrige ; NULL pour une
--     facture. Comme FEORIG (ancien ERP) et UAOIVN (M3), la référence
--     peut être absente ou pointer vers une facture introuvable.
--     Dans les sources, seul le numéro de facture existe ; la ligne est
--     ajoutée ici pour simplifier l'analyse.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE `erp-migration-analytics-js.sql_practice.sales_lines` AS
SELECT *
FROM UNNEST([
    STRUCT(
        'FR' AS entity_id, 'F-1001' AS invoice_number, 1 AS invoice_line_number,
        DATE '2026-08-05' AS invoice_date, 'FR-C001' AS customer_id,
        'HAND-0204' AS product_id, 'invoice' AS document_type,
        CAST(NULL AS STRING) AS credit_note_type, FALSE AS is_intercompany,
        100 AS invoiced_quantity, 12.00 AS list_unit_price_eur,
        0.10 AS discount_rate,
        1080.00 AS net_amount_eur,
        600.00 AS cost_amount_eur,
        CAST(NULL AS STRING) AS original_invoice_number,
        CAST(NULL AS INT64) AS original_invoice_line_number
    ),
    ('FR', 'F-1001', 2, DATE '2026-08-05', 'FR-C001', 'FALL-0031', 'invoice',     NULL,               FALSE,  20, 25.00, 0.20,  400.00,   260.00, NULL,     NULL),
    ('FR', 'F-1002', 1, DATE '2026-08-12', 'FR-C002', 'FOOT-0112', 'invoice',     NULL,               FALSE,  50, 48.00, 0.15, 2040.00,  1250.00, NULL,     NULL),
    ('FR', 'F-1003', 1, DATE '2026-08-20', 'IC-DE',   'HAND-0204', 'invoice',     NULL,               TRUE,  200, 12.00, 0.40, 1440.00,  1200.00, NULL,     NULL),
    ('FR', 'A-2001', 1, DATE '2026-08-28', 'FR-C001', 'HAND-0204', 'credit_note', 'return',           FALSE, -10, 12.00, 0.10, -108.00,   -60.00, 'F-1001', 1),
    ('FR', 'F-1004', 1, DATE '2026-09-03', 'FR-C002', 'HAND-0204', 'invoice',     NULL,               FALSE, 200, 12.00, 0.05, 2280.00,  1200.00, NULL,     NULL),
    ('FR', 'F-1004', 2, DATE '2026-09-03', 'FR-C002', 'FOOT-0112', 'invoice',     NULL,               FALSE,  30, 48.00, 0.10, 1296.00,   750.00, NULL,     NULL),
    ('FR', 'F-1005', 1, DATE '2026-09-15', 'FR-C003', 'FALL-0031', 'invoice',     NULL,               FALSE,  10, 25.00, 0.00,  250.00,   130.00, NULL,     NULL),
    ('FR', 'A-2002', 1, DATE '2026-09-20', 'FR-C002', 'FOOT-0112', 'credit_note', 'price_adjustment', FALSE,   0, NULL,  NULL,   -96.00,     0.00, 'F-1004', 2),
    ('FR', 'F-1006', 1, DATE '2026-09-25', 'IC-DE',   'FALL-0031', 'invoice',     NULL,               TRUE,   40, 25.00, 0.40,  600.00,   520.00, NULL,     NULL),
    ('FR', 'A-2003', 1, DATE '2026-09-28', 'FR-C003', 'FALL-0031', 'credit_note', 'return',           FALSE,  -2, 25.00, 0.00,  -50.00,   -26.00, NULL,     NULL),
    ('DE', 'F-5001', 1, DATE '2026-08-07', 'DE-C010', 'HAND-0204', 'invoice',     NULL,               FALSE, 150, 12.50, 0.12, 1650.00,   900.00, NULL,     NULL),
    ('DE', 'F-5002', 1, DATE '2026-08-18', 'DE-C011', 'FOOT-0112', 'invoice',     NULL,               FALSE,  40, 50.00, 0.20, 1600.00,  1000.00, NULL,     NULL),
    ('DE', 'F-5003', 1, DATE '2026-09-04', 'DE-C010', 'FALL-0031', 'invoice',     NULL,               FALSE,  25, 26.00, 0.10,  585.00,   325.00, NULL,     NULL),
    ('DE', 'F-5004', 1, DATE '2026-09-10', 'DE-C011', 'HAND-0204', 'invoice',     NULL,               FALSE, 300, 12.50, 0.25, 2812.50,  1800.00, NULL,     NULL),
    ('DE', 'A-6001', 1, DATE '2026-09-22', 'DE-C011', 'HAND-0204', 'credit_note', 'return',           FALSE, -20, 12.50, 0.25, -187.50,  -120.00, 'F-5004', 1),
    ('DE', 'F-5005', 1, DATE '2026-09-28', 'IC-FR',   'FOOT-0112', 'invoice',     NULL,               TRUE,   10, 50.00, 0.40,  300.00,   250.00, NULL,     NULL),
    ('DE', 'A-6002', 1, DATE '2026-09-29', 'DE-C010', 'FALL-0031', 'credit_note', 'return',           FALSE,  -5, 26.00, 0.10, -117.00,   -65.00, 'F-5099', 1)
]);
