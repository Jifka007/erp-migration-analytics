-- =====================================================================
-- Thème 2 – Les autres jointures
-- Question 2.3 – La semi-jointure
-- =====================================================================
-- Énoncé : lister les articles du référentiel commandés au moins une fois
--   (une ligne par article, avec son nom), avec EXISTS. Comparer au
--   nombre de lignes d'un INNER JOIN entre products et order_lines, et
--   expliquer pourquoi un SELECT DISTINCT serait une rustine.
-- Tables : sql_practice.products, sql_practice.order_lines
-- Date de référence : 2026-09-30
-- ---------------------------------------------------------------------
-- Grain du résultat : une ligne = un article du référentiel commandé au
--   moins une fois.
--   Pour comparaison, INNER JOIN products × order_lines : une ligne = un
--   couple (article, ligne de commande de cet article).
--
-- Prédiction de contrôle (avant d'exécuter) :
--   1. Nombre de lignes :
--      - semi-jointure (EXISTS ou CTE) : 3 articles, HAND-0204, FALL-0031
--        et FOOT-0112 ;
--      - INNER JOIN : 10 lignes, une par ligne de commande dont l'article
--        est connu (HAND-0204 : 3, FALL-0031 : 3, FOOT-0112 : 4).
--   2. Totaux de contrôle :
--      - 3 articles commandés + 2 jamais commandés (question 2.2) = 5,
--        tout le référentiel ;
--      - 10 lignes de l'INNER JOIN = les 10 lignes gardées en 2.1 ;
--      - dans la version CTE : SUM(order_line_count) = 10.
--   3. Cas limites :
--      - FOOT-0112, commandé 4 fois, doit sortir une seule fois ;
--      - HAND-0310, commandé mais absent du référentiel, ne sort pas : on
--        part du référentiel.
--
-- Raisonnement :
--   - Semi-jointure : garder les lignes de A qui ont AU MOINS un
--     partenaire dans B, chacune une seule fois, sans ramener de
--     colonne de B.
--   - Un INNER JOIN fait bien le filtre, mais il répète chaque article
--     autant de fois qu'il a de lignes de commande (fan-out) : il répond
--     à « une ligne par couple », pas à « une ligne par article ».
--   - Deux écritures justes : EXISTS (un test par article) ou une CTE qui
--     réduit order_lines à une ligne par article avant la jointure.
-- ---------------------------------------------------------------------

-- (1) Méthode EXISTS : la semi-jointure standard
SELECT
    p.product_id,
    p.product_name
FROM sql_practice.products AS p
WHERE EXISTS (
    SELECT 1                                -- seule l'existence compte
    FROM sql_practice.order_lines AS ol
    WHERE ol.product_id = p.product_id      -- corrélation : l'article en cours
)
ORDER BY
    p.product_id;

-- (2) Méthode CTE agrégée + INNER JOIN : ma méthode par défaut
--     La CTE réduit les lignes de commande à une ligne par article
--     commandé : la jointure ne peut plus multiplier les lignes, et on
--     peut ajouter des mesures (ici le nombre de lignes de commande).
WITH ordered_products AS (
    SELECT
        ol.product_id,
        COUNT(*) AS order_line_count
    FROM sql_practice.order_lines AS ol
    GROUP BY
        ol.product_id
)

SELECT
    p.product_id,
    p.product_name,
    op.order_line_count
FROM sql_practice.products AS p
INNER JOIN ordered_products AS op
    ON p.product_id = op.product_id
ORDER BY
    p.product_id;

-- (3) Comparaison : le simple INNER JOIN et son nombre de lignes
SELECT
    COUNT(*) AS inner_join_row_count
FROM sql_practice.products AS p
INNER JOIN sql_practice.order_lines AS ol
    ON p.product_id = ol.product_id;

-- ---------------------------------------------------------------------
-- Résultat obtenu : (1) et (2) : 3 articles, HAND-0204, FALL-0031,
--   FOOT-0112 (en (2), 3, 3 et 4 lignes de commande) ; (3) : 10 lignes.
-- Écart avec la prédiction : aucun.
--
-- Pourquoi SELECT DISTINCT sur l'INNER JOIN serait une rustine :
--   - on fabrique 10 lignes pour en effacer 7 : on répare une erreur de
--     grain au lieu de l'éviter ;
--   - la réparation casse dès qu'on ajoute une colonne de order_lines
--     (une date, un client) : les lignes ne sont plus identiques et le
--     DISTINCT ne déduplique plus ;
--   - il ne protège pas un calcul : SUM(p.list_unit_price_eur) sur
--     l'INNER JOIN compte FOOT-0112 quatre fois ;
--   - il cache un vrai doublon : un article présent deux fois par erreur
--     dans le référentiel serait fusionné sans qu'on le voie.
--
-- =====================================================================
-- Variantes
-- =====================================================================
-- IN (sous-requête) : la plus courte à lire, sans problème de NULL
-- (contrairement à NOT IN), mais limitée à une clé d'une seule colonne.
--
--   WHERE p.product_id IN (
--       SELECT
--           ol.product_id
--       FROM sql_practice.order_lines AS ol
--   )
--
-- INTERSECT DISTINCT : renvoie seulement les codes présents des deux
-- côtés ; utile pour un contrôle rapide, pas pour une liste avec noms.
--
--   SELECT p.product_id FROM sql_practice.products AS p
--   INTERSECT DISTINCT
--   SELECT ol.product_id FROM sql_practice.order_lines AS ol
--
-- Extension : les articles commandés plus souvent que la moyenne.
-- Un agrégat (AVG) ne peut pas être dans le WHERE, qui lit les lignes
-- une par une : on calcule la moyenne dans une CTE d'une ligne, collée
-- par CROSS JOIN (même principe que la CTE parameters).
--
--   WITH ordered_products AS (
--       SELECT
--           ol.product_id,
--           COUNT(*) AS order_line_count
--       FROM sql_practice.order_lines AS ol
--       GROUP BY
--           ol.product_id
--   ),
--
--   order_line_count_average AS (
--       SELECT
--           AVG(op.order_line_count) AS avg_order_line_count
--       FROM ordered_products AS op
--   )
--
--   SELECT
--       p.product_id,
--       p.product_name,
--       op.order_line_count,
--       olca.avg_order_line_count
--   FROM sql_practice.products AS p
--   INNER JOIN ordered_products AS op
--       ON p.product_id = op.product_id
--   CROSS JOIN order_line_count_average AS olca
--   WHERE op.order_line_count > olca.avg_order_line_count
--   ORDER BY
--       op.order_line_count DESC
--
--   La moyenne de quoi ? Sur les articles commandés (3, 3, 4 : 3,33),
--   seul FOOT-0112 est au-dessus. Sur tout le référentiel, en comptant 0
--   pour les articles jamais commandés (moyenne 2), les trois le sont.
--   Le choix se fait et s'écrit avant de calculer.
--
-- Ce que je retiens :
--   - Semi-jointure = « au moins un partenaire », chaque ligne une fois,
--     sans colonne de B : WHERE EXISTS, ou CTE agrégée à la clé puis
--     INNER JOIN (ma méthode, qui permet d'ajouter des mesures).
--   - B sert seulement de filtre : EXISTS. B apporte des mesures : CTE
--     agrégée, puis jointure.
--   - Un DISTINCT juste après une jointure signale un fan-out : chercher
--     quelle jointure a multiplié les lignes plutôt que les effacer.
--   - EXISTS est un opérateur (une condition vrai/faux), placé dans une
--     clause WHERE ; la sous-requête est corrélée : elle fait référence
--     à la ligne en cours (p.product_id).
