-- =====================================================================
-- Entraînement SQL, thème 1 : jointures et grain
-- Petites tables à l'image du modèle du projet (document 01, section 1).
-- À exécuter une seule fois dans la console BigQuery.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS `erp-migration-analytics-js.sql_practice`
OPTIONS (location = 'EU');

-- ---------------------------------------------------------------------
-- Une ligne = une ligne de commande
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE `erp-migration-analytics-js.sql_practice.order_lines` AS
SELECT *
FROM UNNEST([
    STRUCT(
        'FR' AS entity_id, '45872' AS order_number, 1 AS order_line_number,
        'FR-C001' AS customer_id, 'HAND-0204' AS product_id,
        DATE '2026-09-01' AS order_date, DATE '2026-09-10' AS first_promised_date,
        100 AS ordered_quantity, 0 AS cancelled_quantity, 10.00 AS net_unit_price_eur
    ),
    ('FR', '45872', 2, 'FR-C001', 'FALL-0031', DATE '2026-09-01', DATE '2026-09-10',  20,  0, 20.00),
    ('FR', '45901', 1, 'FR-C002', 'FOOT-0112', DATE '2026-09-03', DATE '2026-09-12',  50,  0, 40.00),
    ('FR', '45901', 2, 'FR-C002', 'HAND-0204', DATE '2026-09-03', DATE '2026-09-12', 200,  0,  9.50),
    ('FR', '45933', 1, 'FR-C003', 'FOOT-0112', DATE '2026-09-08', DATE '2026-09-18',  30,  0, 41.00),
    ('FR', '45940', 1, 'FR-C001', 'FALL-0031', DATE '2026-09-10', DATE '2026-09-20',  10,  0, 20.00),
    ('FR', '45940', 2, 'FR-C001', 'HAND-0310', DATE '2026-09-10', DATE '2026-09-20',  80, 20,  3.00),
    ('DE', '45872', 1, 'DE-C010', 'HAND-0204', DATE '2026-09-05', DATE '2026-09-15', 120,  0, 10.50),
    ('DE', '45990', 1, 'DE-C011', 'FOOT-0112', DATE '2026-09-15', DATE '2026-09-25',  40,  0, 39.00),
    ('DE', '45990', 2, 'DE-C011', 'FALL-0031', DATE '2026-09-15', DATE '2026-09-25',  15,  0, 21.00),
    ('DE', '46012', 1, 'DE-C010', 'HAND-0310', DATE '2026-09-25', DATE '2026-10-06',  60,  0,  3.10),
    ('FR', '46020', 1, 'FR-C003', 'FOOT-0112', DATE '2026-09-28', DATE '2026-10-08',  25,  0, 41.00)
]);

-- ---------------------------------------------------------------------
-- Une ligne = une expédition d'une ligne de commande
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE `erp-migration-analytics-js.sql_practice.deliveries` AS
SELECT *
FROM UNNEST([
    STRUCT(
        'L-901' AS delivery_number, 'FR' AS entity_id, '45872' AS order_number,
        1 AS order_line_number, 'FR-APT' AS warehouse_id,
        DATE '2026-09-09' AS shipped_date, 100 AS shipped_quantity
    ),
    ('L-902', 'FR', '45872', 2, 'FR-APT', DATE '2026-09-09',  12),
    ('L-931', 'FR', '45872', 2, 'FR-APT', DATE '2026-09-16',   8),
    ('L-910', 'FR', '45901', 1, 'FR-APT', DATE '2026-09-12',  50),
    ('L-911', 'FR', '45901', 2, 'FR-APT', DATE '2026-09-11', 120),
    ('L-912', 'FR', '45901', 2, 'FR-APT', DATE '2026-09-12',  80),
    ('L-925', 'FR', '45933', 1, 'FR-APT', DATE '2026-09-22',  30),
    ('L-940', 'FR', '45940', 2, 'FR-APT', DATE '2026-09-19',  60),
    ('L-950', 'DE', '45872', 1, 'FR-APT', DATE '2026-09-14', 120),
    ('L-960', 'DE', '45990', 1, 'FR-APT', DATE '2026-09-24',  40),
    ('L-961', 'DE', '45990', 2, 'FR-APT', DATE '2026-09-24',  10)
]);
