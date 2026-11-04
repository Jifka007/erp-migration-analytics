-- =====================================================================
-- Thème 2 – Les autres jointures
-- Question 2.5 – Le contrôle de la migration
-- =====================================================================
-- Énoncé : pour chaque ligne de l'ancien ERP migrée : le nombre de reprises
--   dans M3, la quantité reprise, l'écart avec la quantité ouverte, et un
--   statut : 'matched' (une reprise, même quantité), 'quantity_mismatch',
--   'duplicate' (plus d'une reprise) ou 'missing_in_m3'.
--   Règle affinée après discussion (plus proche de la réalité) : plusieurs
--   reprises dont le total égale la quantité ouverte sont un fractionnement
--   ('split'), pas un doublon ; 'duplicate' quand chaque reprise reprend
--   toute la quantité ; 'duplicate_with_quantity_gap' sinon. Des
--   indicateurs séparés gardent les anomalies cumulées. Puis les lignes
--   M3 sans ligne d'origine. Dire quelle ligne M3 sans référence ressemble
--   à une ligne de l'ancien ERP non reprise, et ce qu'il faudrait pour la
--   rapprocher (thème 7).
-- Tables : sql_practice.legacy_migrated_lines, sql_practice.m3_migrated_lines
-- Date de référence : 2026-09-30
-- ---------------------------------------------------------------------
-- Grain du résultat :
--   (1) une ligne = une ligne de l'ancien ERP migrée (6 lignes) ;
--   (2) une ligne = une ligne M3 sans ligne d'origine ;
--   (3) contrôle : une seule ligne, les totaux des deux systèmes.
--   Étape 1 (migration_line_comparison, question 2.4) : une ligne = un
--     couple (ligne d'origine, reprise), ou une ligne restée seule (9).
--   Étape 2 (legacy_line_reprises) : une ligne = une ligne de l'ancien
--     ERP, avec ses reprises agrégées (6).
--
-- Prédiction de contrôle (avant d'exécuter) :
--   1. Statut des 6 lignes de l'ancien ERP :
--      | ligne       | ouvert | reprises | repris | écart | statut            |
--      | FR 31001/1  |     40 |        1 |     40 |     0 | matched           |
--      | FR 31001/2  |      5 |        1 |      5 |     0 | matched           |
--      | FR 31015/1  |     12 |        0 |      0 |   −12 | missing_in_m3     |
--      | FR 31020/1  |    100 |        0 |      0 |  −100 | missing_in_m3     |
--      | DE 22040/1  |     30 |        2 |     60 |   +30 | duplicate         |
--      | DE 22051/1  |      8 |        1 |     10 |    +2 | quantity_mismatch |
--   2. Lignes M3 orphelines : FR 50007/1 (référence vide, FOOT-0112, 12)
--      et FR 50011/1 (référence 31099/1 inexistante, FALL-0031, 20).
--   3. Totaux de contrôle :
--      - ouvert dans l'ancien ERP : 40 + 5 + 12 + 100 + 30 + 8 = 195 ;
--      - repris dans M3 : 40 + 5 + 12 + 30 + 30 + 10 + 20 = 147 ;
--      - écart M3 − ancien ERP = −48, qui se décompose en :
--          doublon (22040/1)              +30
--          écart de quantité (22051/1)     +2
--          lignes non reprises          −112  (−12 − 100)
--          lignes M3 orphelines          +32  (+12 + 20)
--          total                         −48
--
-- Raisonnement :
--   - On repart de la comparaison de la question 2.4, puis on se place au
--     grain de la ligne d'origine : une ligne par ligne de l'ancien ERP.
--     Ligne par ligne, le doublon de 22040/1 est invisible (30 = 30 sur
--     chacune des deux reprises) ; agrégé, il apparaît (2 reprises, 60).
--   - On garde les lignes qui ont un côté ancien ERP (match_side <>
--     'm3_only'), on regroupe par la clé de la ligne d'origine (entity_id,
--     legacy_order_number, legacy_line_number) et par ses attributs
--     (produit, quantité ouverte), qui ne changent pas le grain.
--   - Nombre de reprises : COUNTIF(match_side = 'both'). Une ligne
--     legacy_only donne 0 (COUNT(*) donnerait 1 : elle a une ligne).
--   - Quantité reprise : 0 pour une ligne jamais reprise (COALESCE). Ici,
--     l'absence de reprise est une information connue : 0 pièce dans M3.
--     L'écart vaut alors −open_quantity : les pièces perdues à la bascule.
--     (En 2.4, ligne par ligne, l'écart restait NULL pour une ligne seule :
--     il n'y avait rien à comparer sur cette ligne.)
--   - Statut selon le nombre de reprises et la quantité totale reprise :
--     | reprises | quantité reprise              | statut                      |
--     | 0        | —                             | missing_in_m3               |
--     | 1        | = ouverte                     | matched                     |
--     | 1        | ≠ ouverte                     | quantity_mismatch           |
--     | 2 ou +   | = ouverte                     | split (fractionnement)      |
--     | 2 ou +   | = ouverte × nombre de reprises | duplicate                  |
--     | 2 ou +   | autre                         | duplicate_with_quantity_gap |
--   - Un CASE ne donne qu'un statut : il sert à lire et à compter. Les
--     indicateurs is_missing_in_m3, is_duplicate, has_quantity_gap gardent
--     toutes les anomalies d'une ligne, qui peut en cumuler plusieurs.
-- ---------------------------------------------------------------------

-- (1) Statut de chaque ligne de l'ancien ERP migrée
WITH migration_line_comparison AS (
    SELECT
        COALESCE(lml.entity_id, m3.entity_id) AS entity_id,
        lml.legacy_order_number,
        lml.legacy_line_number,
        lml.product_id                        AS legacy_product_id,
        lml.open_quantity,
        m3.order_number                       AS m3_order_number,
        m3.order_line_number                  AS m3_order_line_number,
        m3.product_id                         AS m3_product_id,
        m3.ordered_quantity,
        m3.migration_order_number,
        m3.migration_line_number,
        CASE
            WHEN lml.legacy_order_number IS NOT NULL
                AND m3.order_number IS NOT NULL THEN 'both'
            WHEN m3.order_number IS NULL THEN 'legacy_only'
            ELSE 'm3_only'
        END                                   AS match_side
    FROM sql_practice.legacy_migrated_lines AS lml
    FULL OUTER JOIN sql_practice.m3_migrated_lines AS m3
        ON  lml.entity_id           = m3.entity_id
        AND lml.legacy_order_number = m3.migration_order_number
        AND lml.legacy_line_number  = m3.migration_line_number
),

legacy_line_reprises AS (
    SELECT
        mlc.entity_id,
        mlc.legacy_order_number,
        mlc.legacy_line_number,
        mlc.legacy_product_id,
        mlc.open_quantity,
        COUNTIF(mlc.match_side = 'both')       AS m3_line_count,
        COALESCE(SUM(mlc.ordered_quantity), 0) AS m3_ordered_quantity
    FROM migration_line_comparison AS mlc
    WHERE mlc.match_side <> 'm3_only'
    GROUP BY
        mlc.entity_id,
        mlc.legacy_order_number,
        mlc.legacy_line_number,
        mlc.legacy_product_id,
        mlc.open_quantity
)

SELECT
    llr.entity_id,
    llr.legacy_order_number,
    llr.legacy_line_number,
    llr.legacy_product_id,
    llr.open_quantity,
    llr.m3_line_count,
    llr.m3_ordered_quantity,
    llr.m3_ordered_quantity - llr.open_quantity AS quantity_gap,
    CASE
        WHEN llr.m3_line_count = 0 THEN 'missing_in_m3'
        WHEN llr.m3_line_count = 1
            AND llr.m3_ordered_quantity = llr.open_quantity THEN 'matched'
        WHEN llr.m3_line_count = 1 THEN 'quantity_mismatch'
        WHEN llr.m3_ordered_quantity = llr.open_quantity THEN 'split'
        WHEN llr.m3_ordered_quantity
            = llr.open_quantity * llr.m3_line_count THEN 'duplicate'
        ELSE 'duplicate_with_quantity_gap'
    END                                         AS migration_status,
    llr.m3_line_count = 0                       AS is_missing_in_m3,
    llr.m3_line_count > 1
        AND llr.m3_ordered_quantity <> llr.open_quantity
                                                AS is_duplicate,
    llr.m3_line_count >= 1
        AND llr.m3_ordered_quantity
            <> llr.open_quantity * llr.m3_line_count
        AND llr.m3_ordered_quantity <> llr.open_quantity
                                                AS has_quantity_gap
FROM legacy_line_reprises AS llr
ORDER BY
    llr.entity_id,
    llr.legacy_order_number,
    llr.legacy_line_number;

-- (2) Lignes M3 sans ligne d'origine
WITH migration_line_comparison AS (
    SELECT
        COALESCE(lml.entity_id, m3.entity_id) AS entity_id,
        lml.legacy_order_number,
        lml.legacy_line_number,
        lml.product_id                        AS legacy_product_id,
        lml.open_quantity,
        m3.order_number                       AS m3_order_number,
        m3.order_line_number                  AS m3_order_line_number,
        m3.product_id                         AS m3_product_id,
        m3.ordered_quantity,
        m3.migration_order_number,
        m3.migration_line_number,
        CASE
            WHEN lml.legacy_order_number IS NOT NULL
                AND m3.order_number IS NOT NULL THEN 'both'
            WHEN m3.order_number IS NULL THEN 'legacy_only'
            ELSE 'm3_only'
        END                                   AS match_side
    FROM sql_practice.legacy_migrated_lines AS lml
    FULL OUTER JOIN sql_practice.m3_migrated_lines AS m3
        ON  lml.entity_id           = m3.entity_id
        AND lml.legacy_order_number = m3.migration_order_number
        AND lml.legacy_line_number  = m3.migration_line_number
)

SELECT
    mlc.entity_id,
    mlc.m3_order_number,
    mlc.m3_order_line_number,
    mlc.m3_product_id,
    mlc.ordered_quantity,
    mlc.migration_order_number,
    mlc.migration_line_number,
    CASE
        WHEN mlc.migration_order_number IS NULL THEN 'missing_reference'
        ELSE 'unknown_reference'
    END AS orphan_reason
FROM migration_line_comparison AS mlc
WHERE mlc.match_side = 'm3_only'
ORDER BY
    mlc.entity_id,
    mlc.m3_order_number,
    mlc.m3_order_line_number;

-- (3) Contrôle : les totaux des deux systèmes
WITH legacy_totals AS (
    SELECT
        SUM(lml.open_quantity) AS legacy_open_quantity
    FROM sql_practice.legacy_migrated_lines AS lml
),

m3_totals AS (
    SELECT
        SUM(m3.ordered_quantity) AS m3_ordered_quantity
    FROM sql_practice.m3_migrated_lines AS m3
)

SELECT
    lt.legacy_open_quantity,
    mt.m3_ordered_quantity,
    mt.m3_ordered_quantity - lt.legacy_open_quantity AS quantity_gap
FROM legacy_totals AS lt
CROSS JOIN m3_totals AS mt;

-- ---------------------------------------------------------------------
-- Résultat obtenu : (1) 2 matched, 2 missing_in_m3, 1 duplicate,
--   1 quantity_mismatch, conformes au tableau de prédiction ;
--   (2) FR 50007/1 (missing_reference) et FR 50011/1 (unknown_reference) ;
--   (3) 195 ouverts, 147 repris, écart −48.
-- Écart avec la prédiction : aucun.
--
-- La ligne M3 qui ressemble à une ligne non reprise :
--   FR 50007/1 (FOOT-0112, 12 pièces, référence vide) et FR 31015/1
--   (FOOT-0112, 12 pièces ouvertes, jamais reprise). Même filiale, même
--   article, même quantité : très probablement la même ligne, reprise
--   sans noter son origine. Pour la rapprocher, il faut une règle sans
--   référence : même filiale, même client, même article, quantité reprise
--   égale à la quantité ouverte, date demandée proche ; et vérifier
--   qu'il n'y a qu'un seul candidat. C'est le statut « probable » de
--   map_transactions, au thème 7. Si on l'accepte, 31015/1 passe de
--   missing_in_m3 à matched et 50007/1 n'est plus orpheline. L'écart
--   total ne change pas (−48) : seule sa décomposition change, les −12
--   de ligne non reprise et les +12 de ligne orpheline s'annulent.
--   Restent : doublon +30, écart de quantité +2, ligne perdue −100,
--   orpheline 50011/1 +20.
--
-- Ce que je retiens :
--   - Pour contrôler une reprise, on se place au grain de la ligne
--     d'origine : on agrège ses reprises (nombre, quantité). Ligne par
--     ligne, un doublon reste invisible.
--   - COUNTIF(condition) compte les vraies reprises ; COUNT(*) compterait
--     aussi la ligne legacy_only elle-même.
--   - NULL ou 0 selon le grain : en 2.4 (ligne par ligne), pas de
--     partenaire = rien à comparer, NULL ; en 2.5 (par ligne d'origine),
--     pas de reprise = 0 pièce dans M3, une information.
--   - Plusieurs reprises ne veulent pas toujours dire un doublon : si leur
--     total égale la quantité ouverte, c'est un fractionnement, normal. On
--     classe d'après la cause, pas d'après la conséquence.
--   - Un statut unique pour lire, des indicateurs vrai/faux pour garder
--     les anomalies cumulées (même principe que la décomposition des
--     mesures).
--   - Un écart de totaux entre deux systèmes s'explique toujours
--     par une décomposition dont la somme retombe sur l'écart : c'est le
--     principe du pont de réconciliation (thème 11).
--   - Dans le projet : c'est le cœur de map_transactions et de la ligne
--     « doublons de migration » du journal de réconciliation (question 5).
