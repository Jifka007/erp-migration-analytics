-- =====================================================================
-- Thème 2 – Les autres jointures
-- Question 2.4 – Comparer deux systèmes
-- =====================================================================
-- Énoncé : comparer les lignes de l'ancien ERP migrées à la bascule
--   (legacy_migrated_lines) et leur reprise dans M3 (m3_migrated_lines),
--   reliées par la référence de migration (migration_order_number,
--   migration_line_number) dans la même filiale. Une ligne par couple, ou
--   par ligne restée seule, avec une colonne match_side : 'both',
--   'legacy_only' ou 'm3_only'. Puis le nombre de lignes par match_side.
-- Tables : sql_practice.legacy_migrated_lines, sql_practice.m3_migrated_lines
-- Date de référence : 2026-09-30
-- ---------------------------------------------------------------------
-- Grain du résultat :
--   (1) détail : une ligne = une ligne de l'ancien ERP associée à une de
--       ses reprises dans M3, ou une ligne restée seule d'un côté ;
--   (2) résumé : une ligne = une valeur de match_side (3 lignes).
--
-- Prédiction de contrôle (avant d'exécuter) :
--   1. Nombre de lignes du détail : 9.
--      - both : 5 (4 lignes d'origine distinctes, dont DE 22040/1 reprise
--        deux fois : 60002/1 et 60009/1) ;
--      - legacy_only : 2 (FR 31015/1, FR 31020/1) ;
--      - m3_only : 2 (FR 50007/1, FR 50011/1).
--   2. Totaux de contrôle :
--      - côté M3 : 5 both + 2 m3_only = 7, les 7 lignes de M3 (chaque
--        ligne M3 a au plus une ligne d'origine : elle apparaît une fois) ;
--      - côté ancien ERP : 4 lignes reprises + 2 legacy_only = 6, les 6
--        lignes de l'ancien ERP, sur 7 lignes du résultat à cause du
--        doublon ;
--      - total : 5 + 2 + 2 = 9, ni 6 ni 7.
--   3. Cas limites :
--      - FR 50007/1 : référence de migration vide, donc m3_only ;
--      - FR 50011/1 : référence remplie (31099/1) vers une ligne qui
--        n'existe pas parmi les lignes migrées, donc m3_only ;
--      - DE 22040/1 : deux reprises, donc deux lignes both.
--
-- Raisonnement :
--   - FULL OUTER JOIN : garde les lignes des deux tables, appariées quand
--     la condition est vraie, seules sinon (colonnes de l'autre côté à
--     NULL). Une ligne du résultat vient toujours d'au moins une table :
--     les deux côtés ne sont jamais NULL en même temps.
--   - Condition de jointure : la filiale, la commande d'origine et la
--     ligne d'origine (clé complète de l'ancien ERP).
--   - entity_id existe des deux côtés : COALESCE en fait une seule colonne,
--     remplie quel que soit le côté présent.
--   - match_side teste UNE COLONNE DE LA CLÉ de chaque côté
--     (legacy_order_number, m3.order_number) : une colonne de clé n'est
--     jamais NULL quand la ligne existe, donc une seule suffit. Jamais une
--     colonne qui peut être vide pour une autre raison
--     (migration_order_number est NULL sur 50007/1, qui existe bien).
--   - Les colonnes des deux systèmes sont renommées (legacy_…, m3_…) :
--     deux colonnes de même nom sont refusées, et on voit d'où vient
--     chaque numéro.
--   - Les références de migration sont gardées : elles expliquent pourquoi
--     une ligne M3 reste seule.
-- ---------------------------------------------------------------------

-- (1) Détail
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
    mlc.legacy_order_number,
    mlc.legacy_line_number,
    mlc.legacy_product_id,
    mlc.open_quantity,
    mlc.m3_order_number,
    mlc.m3_order_line_number,
    mlc.m3_product_id,
    mlc.ordered_quantity,
    mlc.migration_order_number,
    mlc.migration_line_number,
    mlc.match_side
FROM migration_line_comparison AS mlc
ORDER BY
    mlc.entity_id,
    mlc.legacy_order_number,
    mlc.legacy_line_number,
    mlc.m3_order_number;

-- (2) Résumé (la CTE ne vaut que pour l'instruction qui la suit : on la répète)

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
    mlc.match_side,
    COUNT(*) AS row_count
FROM migration_line_comparison AS mlc
GROUP BY
    mlc.match_side
ORDER BY
    mlc.match_side;

-- ---------------------------------------------------------------------
-- Résultat obtenu : 9 lignes ; both = 5, legacy_only = 2, m3_only = 2.
-- Écart avec la prédiction : aucun.
--
-- Ce que montre la comparaison :
--   - DE 22040/1 : reprise deux fois (60002/1 et 60009/1). Doublon de
--     migration : 60 pièces attendues dans M3 pour 30 restant à livrer.
--   - FR 31020/1 : 100 pièces HAND-0310 jamais reprises dans M3. Commande
--     client perdue à la bascule, le cas le plus grave.
--   - FR 50007/1 et FR 31015/1 : même filiale, même article (FOOT-0112),
--     même quantité (12), mais la référence de migration de 50007/1 est
--     vide. Probablement la même ligne, reprise sans noter son origine :
--     rapprochement « probable », au programme du thème 7.
--   - FR 50011/1 : référence vers 31099/1, qui n'existe pas parmi les
--     lignes migrées. Erreur de saisie ou commande hors périmètre.
--   - DE 22051/1 : appariée, mais 10 pièces reprises pour 8 ouvertes.
--     Le FULL OUTER JOIN ne le signale pas : contrôle de quantité en 2.5.
--
-- Ce que je retiens :
--   - FULL OUTER JOIN pour comparer deux sources : on voit ce qui est des
--     deux côtés, et ce qui n'est que d'un côté, en une seule requête.
--   - COALESCE sur les colonnes communes (entity_id), et les identifiants
--     des deux côtés affichés et renommés : une ligne seule doit dire de
--     quelle table elle vient.
--   - Le côté présent se teste sur une colonne de la clé de chaque table
--     (une seule suffit : aucune colonne de clé n'est NULL quand la ligne
--     existe).
--   - Contrôle : chaque table se retrouve entière dans le résultat
--     (M3 : both + m3_only = 7 ; ancien ERP : lignes reprises distinctes
--     + legacy_only = 6). Un total supérieur à la plus grande table
--     signale des doublons ou des orphelins.
--   - Dans le projet : c'est la base de map_transactions et du journal
--     de réconciliation (question 5).
