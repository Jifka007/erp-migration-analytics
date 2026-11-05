-- =====================================================================
-- Thème 3 – Agrégations conditionnelles
-- Question 3.3 – La remise moyenne pondérée
-- =====================================================================
-- Énoncé : une ligne par article, factures aux clients extérieurs
--   uniquement (ni avoirs, ni ventes internes), avec : la quantité
--   facturée, le prix net moyen par pièce, la remise moyenne simple
--   (moyenne des discount_rate) et la remise moyenne pondérée (montant
--   des remises ÷ montant au prix catalogue). Expliquer l'écart entre les
--   deux remises, et pourquoi on exclut les avoirs.
-- Tables : sql_practice.sales_lines
-- Date de référence : 2026-09-30
-- ---------------------------------------------------------------------
-- Grain du résultat : une ligne = un article vendu (product_id).
--   Une seule étape : filtre dans le WHERE, puis GROUP BY product_id.
--
-- Prédiction de contrôle (calcul à la main sur HAND-0204) :
--   1. Nombre de lignes : 3 (HAND-0204, FOOT-0112, FALL-0031) ;
--      FOOT-0200 et HEAD-0005 n'ont jamais été vendus et n'apparaissent
--      pas, puisque la requête part de sales_lines.
--   2. HAND-0204 : 4 lignes retenues (F-1001/1, F-1004/1, F-5001/1,
--      F-5004/1) ; F-1003 (interne), A-2001 et A-6001 (avoirs) écartés.
--      - quantité : 100 + 200 + 150 + 300 = 750 ;
--      - prix net moyen : (1080 + 2280 + 1650 + 2812.50) / 750
--        = 7822.50 / 750 = 10.43 ;
--      - remise simple : (0.10 + 0.05 + 0.12 + 0.25) / 4 = 0.13 ;
--      - remise pondérée : catalogue 100×12 + 200×12 + 150×12.50
--        + 300×12.50 = 9225 ; remises 9225 - 7822.50 = 1402.50 ;
--        1402.50 / 9225 = 0.1520.
--   Résultat attendu :
--      | Article   | Quantité | Prix net moyen | Remise simple | Remise pondérée |
--      | FALL-0031 | 55       | 22.45          | 0.10          | 0.1179          |
--      | FOOT-0112 | 120      | 41.13          | 0.15          | 0.1548          |
--      | HAND-0204 | 750      | 10.43          | 0.13          | 0.1520          |
--   3. Cas limites : les prix catalogue diffèrent entre FR (12) et DE
--      (12.50) pour HAND-0204 : chaque ligne est valorisée à son propre
--      prix catalogue, on ne prend pas celui de products.
--
-- Raisonnement :
--   - Prix net moyen et remise pondérée sont des rapports de sommes,
--     comme le taux d'avoirs de la question 3.2 : SAFE_DIVIDE(SUM, SUM).
--   - Remise pondérée = (catalogue - facturé) / catalogue, avec
--     catalogue = SUM(quantité × prix catalogue). On part du montant
--     réellement facturé plutôt que de SUM(discount_rate × quantité ×
--     prix) : c'est le montant facturé qui fait foi.
--   - La remise simple (AVG) donne le même poids à chaque ligne, quelle
--     que soit sa taille.
--   - Deux filtres, valables pour toutes les mesures : dans le WHERE.
-- ---------------------------------------------------------------------

SELECT
    sl.product_id,
    SUM(sl.invoiced_quantity)                                       AS invoiced_quantity,
    SAFE_DIVIDE(SUM(sl.net_amount_eur), SUM(sl.invoiced_quantity))  AS avg_net_unit_price_eur,
    AVG(sl.discount_rate)                                           AS avg_discount_rate,
    SAFE_DIVIDE(
        SUM(sl.invoiced_quantity * sl.list_unit_price_eur) - SUM(sl.net_amount_eur),
        SUM(sl.invoiced_quantity * sl.list_unit_price_eur)
    )                                                               AS weighted_discount_rate
FROM sql_practice.sales_lines AS sl
WHERE sl.document_type = 'invoice'
    AND sl.is_intercompany IS FALSE
GROUP BY
    sl.product_id
ORDER BY
    sl.product_id

-- ---------------------------------------------------------------------
-- Résultat obtenu : conforme au tableau ; HAND-0204 retrouve le calcul
--   à la main (750 ; 10.43 ; 0.13 ; 0.1520).
-- Écart avec la prédiction : aucun.
--
-- Écart entre les deux remises : la remise pondérée (0.152) dépasse la
--   remise simple (0.13) pour HAND-0204 parce que la plus grosse ligne
--   (F-5004, 300 pièces, 3750 € au catalogue) a aussi la plus forte
--   remise (25 %). La moyenne simple lui donne le même poids qu'à F-1001
--   (100 pièces à 10 %). La remise pondérée est la remise réellement
--   accordée en euros, rapportée au chiffre d'affaires au catalogue.
--
-- Pourquoi exclure les avoirs : une remise et un avoir sont deux choses
--   différentes. La remise est négociée avant la vente et écrite sur la
--   facture ; l'avoir corrige la facture après coup. Si on les incluait :
--   | Article   | Quantité  | Prix net moyen  | Remise simple | Remise pondérée  |
--   | HAND-0204 | 750 → 720 | 10.43 → 10.45   | 0.13 → 0.145  | 0.1520 → 0.1500  |
--   | FOOT-0112 | 120 → 120 | 41.13 → 40.33   | 0.15 → 0.15   | 0.1548 → 0.1712  |
--   | FALL-0031 | 55 → 48   | 22.45 → 22.25   | 0.10 → 0.08   | 0.1179 → 0.1246  |
--   - Un retour (A-2001, A-6001, A-2003, A-6002) est une baisse de
--     volume, pas de prix : ses pièces avaient été vendues avec la remise
--     de la facture d'origine. Inclus, il entre dans AVG comme une
--     observation de plus (HAND passe de 4 à 6 taux moyennés : 0.145),
--     et il peut porter sur une vente d'une autre période.
--   - Le geste commercial (A-2002) a une quantité 0, un prix et une
--     remise NULL, et un montant de -96. Chaque formule le traite
--     différemment, sans erreur : AVG ignore la remise NULL (0.15
--     inchangé) ; 0 × NULL = NULL, ignoré par SUM, donc le catalogue ne
--     bouge pas (5840) ; mais le montant facturé baisse de 96, donc la
--     remise pondérée monte (1000 / 5840 = 0.1712). Les deux remises ne
--     mesurent plus la même chose : la remise simple ne voit pas le geste,
--     la pondérée le compte comme une remise.
--   - Un geste commercial est bien une baisse de prix accordée après
--     coup. Pour le prix net réellement encaissé (le pocket price, en
--     cascade : catalogue - remise - gestes commerciaux), on le rattache
--     à la ligne de facture qu'il corrige (original_invoice_number,
--     question 3.5). Mais c'est un autre indicateur que la remise
--     négociée.
--
-- Ce que je retiens :
--   - Remise moyenne = rapport de sommes : (catalogue - facturé) /
--     catalogue ; jamais AVG(discount_rate), qui ne pondère pas.
--   - Prix net moyen = SUM(montant) / SUM(quantité), pas AVG(prix).
--   - Un NULL ne fait pas d'erreur : AVG et SUM l'ignorent en silence,
--     et deux formules peuvent alors traiter la même ligne différemment.
--     Vérifier les NULL avant d'agréger.
--   - Remise (avant, sur la facture) et avoir (après, sur un autre
--     document) : un retour est du volume, un geste commercial est du
--     prix, à analyser à part.
--   - Nommer une mesure par sa méthode (weighted_discount_rate), pas par
--     un jugement (true_…).
