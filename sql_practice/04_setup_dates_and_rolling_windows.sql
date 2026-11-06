-- =====================================================================
-- Entraînement SQL, thème 4 : dates et fenêtres glissantes
-- Deux tables : les factures par client (en-têtes, sur deux ans) et les
-- filiales. Montants en euros. À exécuter une seule fois dans la console
-- BigQuery (région US).
-- Date de référence : 2026-09-30 (fin de journée).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Une ligne = une facture (en-tête) à un client extérieur (16 lignes)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE `erp-migration-analytics-js.sql_practice.customer_invoices` AS
SELECT *
FROM UNNEST([
    STRUCT(
        'FR' AS entity_id, 'F-0101' AS invoice_number,
        DATE '2025-03-14' AS invoice_date, 'FR-C001' AS customer_id,
        1200.00 AS net_amount_eur
    ),
    ('FR', 'F-0102', DATE '2024-11-20', 'FR-C002',  600.00),
    ('FR', 'F-0103', DATE '2025-06-02', 'FR-C002',  700.00),
    ('FR', 'F-0104', DATE '2025-10-01', 'FR-C004',  900.00),
    ('FR', 'F-0105', DATE '2025-11-05', 'FR-C001',  800.00),
    ('FR', 'F-0106', DATE '2026-02-10', 'FR-C001',  950.00),
    ('FR', 'F-0107', DATE '2026-03-03', 'FR-C003',  400.00),
    ('FR', 'F-0108', DATE '2026-03-25', 'FR-C003',  300.00),
    ('FR', 'F-0109', DATE '2026-07-22', 'FR-C001', 1100.00),
    ('FR', 'F-0110', DATE '2026-09-30', 'FR-C003',  500.00),
    ('DE', 'F-0201', DATE '2025-01-15', 'DE-C010', 1500.00),
    ('DE', 'F-0202', DATE '2025-09-30', 'DE-C011', 2000.00),
    ('DE', 'F-0203', DATE '2026-01-20', 'DE-C010', 1300.00),
    ('DE', 'F-0204', DATE '2026-05-11', 'DE-C010', 1250.00),
    ('DE', 'F-0205', DATE '2026-06-18', 'DE-C012',  700.00),
    ('DE', 'F-0206', DATE '2026-08-04', 'DE-C012',  650.00)
]);

-- ---------------------------------------------------------------------
-- Une ligne = une filiale du groupe (2 lignes)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE `erp-migration-analytics-js.sql_practice.entities` AS
SELECT *
FROM UNNEST([
    STRUCT('FR' AS entity_id, 'Delta Plus France' AS entity_name),
    ('DE', 'Delta Plus Germany')
]);
