-- =====================================================================
-- Thème 3 – Agrégations conditionnelles
-- Question 3.4 – Une colonne par gamme, et la marge
-- =====================================================================
-- Énoncé : une ligne par filiale, avec le CA consolidé de chaque
--   gamme dans sa propre colonne (HAND, FOOT, FALL ; la gamme vient de
--   products), le CA consolidé total, la marge brute (CA − coût de
--   revient) et le taux de marge brute (entre 0 et 1). Avoirs compris,
--   ventes internes exclues. Vérifier que la somme des colonnes de gammes
--   égale le CA consolidé total.
-- Tables : sql_practice.sales_lines, sql_practice.products
-- Date de référence : 2026-09-30
-- ---------------------------------------------------------------------
-- Grain du résultat : une ligne = une filiale.
--   Étape 1 (jointure) : une ligne = une ligne de facture ou d'avoir
--     externe, enrichie de sa gamme ; products a une ligne par article,
--     donc pas de fan-out : 15 lignes externes avant et après la jointure.
--   Étape 2 (entity_amounts, après GROUP BY) : une ligne = une filiale.
--
-- Prédiction de contrôle (avant d'exécuter) :
--   1. Nombre de lignes : 2 (FR, DE).
--   2. Totaux de contrôle :
--      | Filiale | HAND    | FOOT    | FALL   | Inconnu | CA      | Coût    | Marge   | Taux   |
--      | DE      | 4275.00 | 1600.00 | 468.00 | 0       | 6343.00 | 3840.00 | 2503.00 | 0.3946 |
--      | FR      | 3252.00 | 3240.00 | 600.00 | 0       | 7092.00 | 4104.00 | 2988.00 | 0.4213 |
--      - DE HAND : 1650 + 2812.50 - 187.50 ; FALL : 585 - 117 ;
--      - FR HAND : 1080 + 2280 - 108 ; FOOT : 2040 + 1296 - 96 ;
--        FALL : 400 + 250 - 50 ;
--      - le CA consolidé retombe sur celui de la question 3.1.
--   3. Cas limites :
--      - un article absent de products : gamme NULL, gardé par le LEFT
--        JOIN, compté dans la colonne inconnu (0 ici) ;
--      - un article connu d'une autre gamme (HEAD) : dans aucune colonne,
--        l'écart de contrôle le révélerait (aucun vendu ici) ;
--      - avoirs : un retour baisse le CA et le coût (la marchandise revient
--        en stock) ; le geste commercial A-2002 baisse le CA, pas le coût
--        (cost_amount_eur = 0), donc il baisse la marge de 96.
--
-- Raisonnement :
--   - La gamme est dans products : LEFT JOIN, pour ne perdre aucune
--     vente. Un INNER JOIN ferait disparaître en silence les ventes d'un
--     article inconnu, et le CA ne retomberait plus sur la question 3.1.
--   - Une colonne par gamme : SUM(IF(p.product_line_id = '…', montant, 0))
--     (pivot manuel). Une colonne de plus pour les articles inconnus
--     (p.product_line_id IS NULL) : le total reste juste et le trou du
--     référentiel devient visible.
--   - Une seule agrégation suffit : les SUM(IF()) se calculent
--     directement sur la jointure. Passer d'abord par le format long
--     (filiale × gamme) puis le repivoter est une bonne étape de
--     vérification, mais demande deux GROUP BY.
--   - La marge, le taux et l'écart se calculent dans le SELECT final à
--     partir des colonnes de la CTE : chaque somme est écrite une fois.
--   - Contrôle en écart arrondi (montants FLOAT), pas en égalité stricte
--     de deux FLOAT : 6342.999999 = 6343 renverrait FALSE.
-- ---------------------------------------------------------------------

WITH entity_amounts AS (
    SELECT
        sl.entity_id,
        SUM(IF(p.product_line_id = 'HAND', sl.net_amount_eur, 0))  AS hand_revenue_amount_eur,
        SUM(IF(p.product_line_id = 'FOOT', sl.net_amount_eur, 0))  AS foot_revenue_amount_eur,
        SUM(IF(p.product_line_id = 'FALL', sl.net_amount_eur, 0))  AS fall_revenue_amount_eur,
        SUM(IF(p.product_line_id IS NULL, sl.net_amount_eur, 0))   AS unknown_product_line_revenue_amount_eur,
        SUM(sl.net_amount_eur)                                     AS consolidated_revenue_amount_eur,
        SUM(sl.cost_amount_eur)                                    AS cost_amount_eur
    FROM sql_practice.sales_lines AS sl
    LEFT JOIN sql_practice.products AS p
        ON  sl.product_id = p.product_id
    WHERE sl.is_intercompany IS FALSE
    GROUP BY
        sl.entity_id
)

SELECT
    ea.entity_id,
    ea.hand_revenue_amount_eur,
    ea.foot_revenue_amount_eur,
    ea.fall_revenue_amount_eur,
    ea.unknown_product_line_revenue_amount_eur,
    ea.consolidated_revenue_amount_eur,
    ea.consolidated_revenue_amount_eur - ea.cost_amount_eur              AS gross_margin_amount_eur,
    SAFE_DIVIDE(
        ea.consolidated_revenue_amount_eur - ea.cost_amount_eur,
        ea.consolidated_revenue_amount_eur
    )                                                                    AS gross_margin_rate,
    ROUND(ea.consolidated_revenue_amount_eur
          - ea.hand_revenue_amount_eur
          - ea.foot_revenue_amount_eur
          - ea.fall_revenue_amount_eur
          - ea.unknown_product_line_revenue_amount_eur, 2)               AS control_gap_amount_eur
FROM entity_amounts AS ea
ORDER BY
    ea.entity_id

-- ---------------------------------------------------------------------
-- Résultat obtenu : conforme au tableau de la prédiction ;
--   DE 4275 / 1600 / 468 / 0, CA 6343, marge 2503, taux 0.3946 ;
--   FR 3252 / 3240 / 600 / 0, CA 7092, marge 2988, taux 0.4213 ;
--   écart de contrôle 0 pour les deux filiales.
-- Écart avec la prédiction : aucun. Première version en deux étapes
--   (format long filiale × gamme, puis pivot) : même résultat.
--
-- Ce que je retiens :
--   - Pivot manuel : une colonne = un SUM(IF(catégorie = '…', montant, 0)).
--     Les catégories sont écrites en dur : une nouvelle gamme demande une
--     nouvelle colonne, d'où la colonne inconnu et l'écart de contrôle.
--   - Enrichir depuis un référentiel : LEFT JOIN, puis rendre visible ce
--     qui n'a pas trouvé de correspondance, au lieu de le perdre.
--   - Distinguer « inconnu du référentiel » (NULL après la jointure) et
--     « connu mais hors des colonnes prévues » : l'écart attrape le second.
--   - Calculer marge, taux et écart à partir des colonnes de la CTE, sans
--     répéter les SUM.
--   - Ne jamais comparer deux FLOAT avec = : un écart arrondi.
--   - Le geste commercial n'a pas de coût : il baisse la marge du montant
--     entier, alors qu'un retour baisse CA et coût ensemble.
--   - Noms : tout en minuscules (hand_…, pas HAND_…), anglais
--     (gross_margin, pas marge_brut), suffixes _amount_eur et _rate.
