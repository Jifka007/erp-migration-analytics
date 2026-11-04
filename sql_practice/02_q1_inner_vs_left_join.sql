-- =====================================================================
-- Thème 2 – Les autres jointures
-- Question 2.1 – INNER ou LEFT : la perte silencieuse
-- =====================================================================
-- Énoncé : joindre order_lines au référentiel products sur product_id,
--   une fois avec INNER JOIN, une fois avec LEFT JOIN. Pour chaque
--   version : le nombre de lignes et le montant commandé total
--   (ordered_quantity × net_unit_price_eur), sur une seule ligne de
--   résultat. Dire quelles lignes de commande disparaissent avec INNER
--   JOIN, pourquoi, et ce que cela change sur le montant.
-- Tables : sql_practice.order_lines, sql_practice.products
-- Date de référence : 2026-09-30
-- ---------------------------------------------------------------------
-- Grain du résultat : une seule ligne, avec quatre valeurs : le nombre de
--   lignes et le montant commandé total, pour l'INNER JOIN et pour le
--   LEFT JOIN.
--   Étape 1 (INNER JOIN) : une ligne = une ligne de commande dont
--     l'article existe dans le référentiel, avec ses informations
--     d'article.
--   Étape 2 (LEFT JOIN) : une ligne = une ligne de commande, avec ses
--     informations d'article, ou des NULL si l'article est inconnu.
--
-- Prédiction de contrôle (avant d'exécuter) :
--   1. Nombre de lignes :
--      - products : 5 lignes, product_id unique (clé primaire) ;
--        order_lines : 12 lignes, product_id y est une clé étrangère.
--      - Une ligne de commande a donc au plus un article (0 si son code
--        est inconnu du référentiel) : aucune jointure ne peut
--        multiplier les lignes.
--      - LEFT JOIN : 12 lignes, toutes les lignes de commande.
--      - INNER JOIN : 10 lignes. Le code HAND-0310 n'existe pas dans
--        products : ses 2 lignes de commande disparaissent.
--   2. Totaux de contrôle :
--      - montant total des 12 lignes = 11 316 € ;
--      - montant des lignes perdues = 240 + 186 = 426 € ;
--      - montant INNER JOIN = 11 316 − 426 = 10 890 €.
--   3. Cas limites : les deux lignes de HAND-0310 :
--      - FR 45940/2 : 80 × 3,00 = 240 € ;
--      - DE 46012/1 : 60 × 3,10 = 186 €.
--
-- Raisonnement :
--   - INNER JOIN ne garde que les lignes qui trouvent un partenaire des
--     deux côtés : une ligne de commande dont l'article est inconnu du
--     référentiel disparaît, sans erreur ni avertissement.
--   - LEFT JOIN garde toutes les lignes de commande ; les colonnes de
--     products valent NULL quand l'article est inconnu.
--   - Le montant se calcule à partir de order_lines seule : la jointure
--     ne change pas le montant d'une ligne, elle décide seulement si la
--     ligne est gardée.
-- ---------------------------------------------------------------------

WITH inner_join_totals AS (
    SELECT
        COUNT(*)                                         AS inner_join_row_count,
        SUM(ol.ordered_quantity * ol.net_unit_price_eur) AS inner_join_ordered_amount_eur
    FROM sql_practice.order_lines AS ol
    INNER JOIN sql_practice.products AS p
        ON ol.product_id = p.product_id
),

left_join_totals AS (
    SELECT
        COUNT(*)                                         AS left_join_row_count,
        SUM(ol.ordered_quantity * ol.net_unit_price_eur) AS left_join_ordered_amount_eur
    FROM sql_practice.order_lines AS ol
    LEFT JOIN sql_practice.products AS p
        ON ol.product_id = p.product_id
)

SELECT
    ijt.inner_join_row_count,
    ijt.inner_join_ordered_amount_eur,
    ljt.left_join_row_count,
    ljt.left_join_ordered_amount_eur
FROM inner_join_totals AS ijt
CROSS JOIN left_join_totals AS ljt

-- ---------------------------------------------------------------------
-- Résultat obtenu : inner_join_row_count = 10,
--   inner_join_ordered_amount_eur = 10 890 ; left_join_row_count = 12,
--   left_join_ordered_amount_eur = 11 316.
-- Écart avec la prédiction : aucun.
--
-- Lignes perdues avec INNER JOIN : FR 45940/2 et DE 46012/1, article
--   HAND-0310, absent du référentiel. 426 € de commandes disparaissent
--   du total, soit 3,8 %, sans aucun message d'erreur.
--
-- Ce que je retiens :
--   - INNER JOIN filtre : il ne garde que ce qui existe des deux côtés.
--     LEFT JOIN conserve : toute la table de gauche, avec des NULL.
--   - Quand la table de droite est un référentiel (articles, taux de
--     change, clients), un INNER JOIN fait disparaître en silence les
--     lignes dont le code est inconnu. Par défaut, LEFT JOIN, puis on
--     compte et on traite les NULL (défaut de qualité).
--   - Contrôle : nombre de lignes et total avant et après la jointure.
--     Un écart signale des codes inconnus (ou un fan-out, s'il y a plus
--     de lignes).
--   - Dans le projet : un taux de change manquant pour un mois, avec un
--     INNER JOIN, ferait disparaître du CA toutes les ventes de ce mois
--     dans cette devise.
