-- =====================================================================
-- Thème 2 – Les autres jointures
-- Question 2.2 – Ce qui n'a pas de correspondant
-- =====================================================================
-- Énoncé : (1) lister les lignes de commande dont l'article est absent du
--   référentiel, écrit de deux façons : LEFT JOIN … IS NULL, puis NOT
--   EXISTS ; (2) lister les articles du référentiel jamais commandés.
--   Expliquer pourquoi NOT IN est à éviter, et ce que ces listes
--   apportent à la page qualité du projet.
-- Tables : sql_practice.order_lines, sql_practice.products
-- Date de référence : 2026-09-30
-- ---------------------------------------------------------------------
-- Grain du résultat :
--   (1) une ligne = une ligne de commande dont l'article est absent du
--       référentiel ;
--   (2) une ligne = un article du référentiel jamais commandé.
--
-- Prédiction de contrôle (avant d'exécuter) :
--   1. Nombre de lignes :
--      - (1) 2 lignes, avec les deux écritures : FR 45940/2 et
--        DE 46012/1 (article HAND-0310, inconnu du référentiel) ;
--      - (2) 2 articles : FOOT-0200 et HEAD-0005.
--   2. Totaux de contrôle :
--      - (1) 12 lignes de commande − 10 gardées par l'INNER JOIN
--        (question 2.1) = 2 ;
--      - (2) 5 articles − 3 articles commandés (HAND-0204, FALL-0031,
--        FOOT-0112) = 2.
--   3. Cas limites : un article commandé plusieurs fois (FOOT-0112,
--      4 lignes) ne doit pas apparaître en (2) ; un article sans commande
--      ne doit apparaître qu'une fois.
--
-- Raisonnement :
--   - Une anti-jointure répond à : « quelles lignes de A n'ont AUCUN
--     partenaire dans B ? ».
--   - Ma méthode par défaut : LEFT JOIN … WHERE <clé de B> IS NULL.
--   - L'autre écriture à savoir lire : NOT EXISTS.
--   - Jamais NOT IN sur une colonne qui peut contenir des NULL.
--   (Détail des trois écritures en fin de fichier.)
-- ---------------------------------------------------------------------

-- (1a) Lignes de commande sans article dans le référentiel
--      Méthode par défaut : LEFT JOIN … IS NULL
SELECT
    ol.entity_id,
    ol.order_number,
    ol.order_line_number,
    ol.product_id,
    ol.ordered_quantity * ol.net_unit_price_eur AS ordered_amount_eur
FROM sql_practice.order_lines AS ol
LEFT JOIN sql_practice.products AS p
    ON ol.product_id = p.product_id
-- Le test porte sur la CLÉ DE JOINTURE DE LA TABLE DE DROITE (p.product_id) :
-- quand il y a un partenaire, elle vaut forcément la valeur du ON, donc
-- jamais NULL. NULL veut alors dire, sans ambiguïté, « pas de partenaire ».
-- Ne jamais tester une autre colonne de p (product_name, prix…) : elle
-- pourrait être vide dans le référentiel pour une autre raison, et la
-- ligne serait prise à tort pour un article inconnu.
WHERE p.product_id IS NULL
ORDER BY
    ol.entity_id,
    ol.order_number,
    ol.order_line_number;

-- (1b) Même liste : NOT EXISTS
SELECT
    ol.entity_id,
    ol.order_number,
    ol.order_line_number,
    ol.product_id,
    ol.ordered_quantity * ol.net_unit_price_eur AS ordered_amount_eur
FROM sql_practice.order_lines AS ol
WHERE NOT EXISTS (
    SELECT 1                                -- seule l'existence compte
    FROM sql_practice.products AS p
    WHERE p.product_id = ol.product_id      -- ol = la ligne en cours
)
ORDER BY
    ol.entity_id,
    ol.order_number,
    ol.order_line_number;

-- (2) Articles du référentiel jamais commandés : LEFT JOIN … IS NULL
--     Ici, la table de droite est order_lines : on teste SA clé de
--     jointure, ol.product_id.
SELECT
    p.product_id,
    p.product_name,
    p.product_line_id
FROM sql_practice.products AS p
LEFT JOIN sql_practice.order_lines AS ol
    ON p.product_id = ol.product_id
WHERE ol.product_id IS NULL
ORDER BY
    p.product_id;

-- ---------------------------------------------------------------------
-- Résultat obtenu : (1a) et (1b) : 2 lignes, FR 45940/2 (240 €) et
--   DE 46012/1 (186 €), article HAND-0310 ; (2) : FOOT-0200 et HEAD-0005.
-- Écart avec la prédiction : aucun.
--
-- =====================================================================
-- LES TROIS ÉCRITURES D'UNE ANTI-JOINTURE
-- =====================================================================
--
-- 1. LEFT JOIN … WHERE <clé de droite> IS NULL  (ma méthode par défaut)
--
--    Le LEFT JOIN garde toutes les lignes de A ; celles qui n'ont pas de
--    partenaire reçoivent des NULL dans toutes les colonnes de B. Le WHERE
--    ne garde que celles-là.
--    Règle : tester la clé de jointure de B, la seule colonne de B dont
--    on est sûr qu'elle n'est jamais NULL quand il y a un partenaire.
--    Avantages : se lit comme une jointure, s'enchaîne avec les CTE, et
--    le même LEFT JOIN peut servir à marquer chaque ligne
--    (p.product_id IS NOT NULL AS has_known_product).
--    Pas de fan-out dans le résultat : les lignes gardées n'ont, par
--    définition, aucun partenaire, donc une seule ligne chacune.
--
-- 2. WHERE NOT EXISTS (sous-requête)  (à savoir lire et expliquer)
--
--    Pour chaque ligne de A, la sous-requête cherche au moins une ligne
--    de B qui correspond (elle fait référence à la ligne en cours :
--    p.product_id = ol.product_id).
--      - Elle en trouve une : EXISTS = TRUE, NOT EXISTS = FALSE, la ligne
--        est écartée.
--      - Elle n'en trouve aucune : NOT EXISTS = TRUE, la ligne est gardée.
--    SELECT 1 : EXISTS ne regarde pas le contenu des lignes renvoyées,
--    seulement s'il y en a au moins une. SELECT *, SELECT 'x' donneraient
--    le même résultat ; SELECT 1 dit au lecteur « je ne lis aucune
--    colonne ».
--    Intérêt de EXISTS / NOT EXISTS :
--      - l'intention se lit en français : « les lignes de commande pour
--        lesquelles il n'existe pas d'article » ;
--      - une ligne de A sort au plus une fois, même si B contient
--        plusieurs partenaires ou des doublons : jamais de fan-out ;
--      - insensible aux NULL ;
--      - EXISTS (sans NOT) est la semi-jointure : « garder les lignes
--        de A qui ont AU MOINS un partenaire », sans les multiplier.
--        Une jointure classique, elle, renverrait une ligne par
--        partenaire (question 2.3).
--    C'est un simple test dans le WHERE, pas une étape de calcul : la
--    règle « remplacer les sous-requêtes par des CTE » ne le vise pas.
--
-- 3. WHERE x NOT IN (sous-requête)  (à éviter)
--
--    WHERE p.product_id NOT IN (SELECT ol.product_id FROM order_lines …)
--    se lit facilement, mais SQL le traduit en une suite de différences :
--      p.product_id <> 'HAND-0204'
--      AND p.product_id <> 'FALL-0031'
--      AND p.product_id <> NULL          <- si une commande n'a pas de code
--      AND ...
--    Or une comparaison avec NULL ne vaut ni TRUE ni FALSE : elle vaut
--    NULL (« inconnu »). Et dans un AND, un seul NULL suffit à empêcher
--    le résultat d'être TRUE :
--      TRUE AND TRUE AND NULL = NULL
--    Le WHERE ne garde que les lignes où la condition vaut TRUE : il ne
--    garde donc plus rien. Une seule ligne de commande sans code article
--    vide la liste des articles jamais commandés, sans aucune erreur.
--    NOT EXISTS et LEFT JOIN … IS NULL n'ont pas ce problème : ils ne
--    comparent pas à une liste, ils cherchent un partenaire, et un NULL
--    n'en trouve simplement pas.
--    (À l'inverse, IN, sans NOT, ne pose pas ce problème : x = NULL vaut
--    NULL, mais dans un OR il suffit qu'une autre comparaison vaille TRUE.)
--
-- Résumé :
--   | Écriture               | Lisible | Sûre avec NULL | Usage               |
--   | LEFT JOIN … IS NULL    | oui     | oui            | ma méthode          |
--   | NOT EXISTS             | oui     | oui            | savoir la lire      |
--   | NOT IN                 | oui     | NON            | jamais si NULL      |
--
-- =====================================================================
-- Ce que ces listes apportent à la page qualité du projet
-- =====================================================================
--   - (1) Lignes de commande dont l'article est inconnu : un défaut de
--     référentiel, à valoriser (426 €) et à corriger à la source (créer
--     l'article ou corriger le code). Dans le projet, ces lignes vont
--     dans fct_data_quality_issues.
--   - (2) Articles jamais commandés : pas un défaut, une information
--     (article nouveau, en fin de vie, ou mal codé dans les commandes).
--     Utile au stock dormant (question 4).
--
-- Ce que je retiens :
--   - Anti-jointure par LEFT JOIN … IS NULL, en testant la clé de
--     jointure de la table de droite.
--   - NOT EXISTS : même résultat, l'intention en français, jamais de
--     fan-out ; à savoir lire et expliquer.
--   - Jamais NOT IN sur une colonne qui peut contenir des NULL : un seul
--     NULL vide le résultat, en silence.
--   - Une anti-jointure se contrôle par différence : lignes de A − lignes
--     gardées par l'INNER JOIN.
