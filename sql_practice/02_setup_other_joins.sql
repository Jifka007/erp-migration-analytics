-- =====================================================================
-- Entraînement SQL, thème 2 : les autres jointures
-- Trois nouvelles tables, à côté de order_lines et deliveries (thème 1).
-- À exécuter une seule fois dans la console BigQuery (région US).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Une ligne = un article du référentiel
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE `erp-migration-analytics-js.sql_practice.products` AS
SELECT *
FROM UNNEST([
    STRUCT(
        'HAND-0204' AS product_id, 'Nitrile glove 204' AS product_name,
        'HAND' AS product_line_id, 9.90 AS list_unit_price_eur
    ),
    ('FALL-0031', 'Fall arrest harness 31', 'FALL', 22.00),
    ('FOOT-0112', 'S3 safety shoe 112',     'FOOT', 45.00),
    ('FOOT-0200', 'PVC boot 200',           'FOOT', 18.00),
    ('HEAD-0005', 'Site helmet 5',          'HEAD', 12.50)
]);

-- ---------------------------------------------------------------------
-- Une ligne = une ligne de commande de l'ancien ERP encore ouverte à la
-- bascule du 7 avril 2026 (statut M : migrée), pour sa quantité restante
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE `erp-migration-analytics-js.sql_practice.legacy_migrated_lines` AS
SELECT *
FROM UNNEST([
    STRUCT(
        'FR' AS entity_id, '31001' AS legacy_order_number, 1 AS legacy_line_number,
        'HAND-0204' AS product_id, 40 AS open_quantity, 'M' AS line_status
    ),
    ('FR', '31001', 2, 'FALL-0031',   5, 'M'),
    ('FR', '31015', 1, 'FOOT-0112',  12, 'M'),
    ('FR', '31020', 1, 'HAND-0310', 100, 'M'),
    ('DE', '22040', 1, 'HAND-0204',  30, 'M'),
    ('DE', '22051', 1, 'FOOT-0112',   8, 'M')
]);

-- ---------------------------------------------------------------------
-- Une ligne = une ligne de commande créée dans M3 à la bascule pour
-- reprendre une ligne ouverte de l'ancien ERP ; la référence de migration
-- (commande et ligne d'origine) n'est pas toujours renseignée
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE `erp-migration-analytics-js.sql_practice.m3_migrated_lines` AS
SELECT *
FROM UNNEST([
    STRUCT(
        'FR' AS entity_id, '50001' AS order_number, 1 AS order_line_number,
        'HAND-0204' AS product_id, 40 AS ordered_quantity,
        '31001' AS migration_order_number, 1 AS migration_line_number
    ),
    ('FR', '50001', 2, 'FALL-0031',  5, '31001', 2),
    ('FR', '50007', 1, 'FOOT-0112', 12, NULL,    NULL),
    ('DE', '60002', 1, 'HAND-0204', 30, '22040', 1),
    ('DE', '60009', 1, 'HAND-0204', 30, '22040', 1),
    ('DE', '60004', 1, 'FOOT-0112', 10, '22051', 1),
    ('FR', '50011', 1, 'FALL-0031', 20, '31099', 1)
]);
