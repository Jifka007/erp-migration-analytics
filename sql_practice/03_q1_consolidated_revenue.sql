-- =====================================================================
-- Thème 3 – Agrégations conditionnelles
-- Question 3.1 – Le CA consolidé par filiale
-- =====================================================================
-- Énoncé : une ligne par filiale, avec : le montant total de toutes
--   les lignes, le montant des ventes internes, le montant des avoirs aux
--   clients extérieurs (négatif), et le CA consolidé (lignes aux clients
--   extérieurs, factures et avoirs compris). Vérifier que le montant total
--   égale ventes internes + CA consolidé.
-- Tables : sql_practice.sales_lines
-- Date de référence : 2026-09-30
-- ---------------------------------------------------------------------
-- Grain du résultat : une ligne = une filiale (entity_id).
--   Une seule étape : un GROUP BY sur entity_id ; chaque colonne est un
--   SUM avec sa propre condition (agrégat conditionnel).
--
-- Prédiction de contrôle (avant d'exécuter) :
--   1. Nombre de lignes : 2 (FR, DE), à partir des 18 lignes de
--      sales_lines (11 FR, 7 DE).
--   2. Totaux de contrôle :
--      | Filiale | Total   | Interne | Avoirs ext. | CA consolidé | Écart |
--      | FR      | 9132.00 | 2040.00 | -254.00     | 7092.00      | 0     |
--      | DE      | 6643.00 |  300.00 | -304.50     | 6343.00      | 0     |
--      - FR : factures externes 7346 (1080 + 400 + 2040 + 2280 + 1296
--        + 250) ; internes 2040 (F-1003 1440 + F-1006 600) ; avoirs
--        externes -254 (A-2001 -108, A-2002 -96, A-2003 -50).
--        CA consolidé = 7346 - 254 = 7092 ; 2040 + 7092 = 9132.
--      - DE : factures externes 6647.50 (1650 + 1600 + 585 + 2812.50) ;
--        interne 300 (F-5005) ; avoirs externes -304.50 (A-6001 -187.50,
--        A-6002 -117). CA consolidé = 6343 ; 300 + 6343 = 6643.
--   3. Cas limites :
--      - A-2002 (geste commercial) : quantité 0, prix et remise NULL,
--        mais montant -96 : il entre dans les avoirs et dans le CA
--        consolidé, puisqu'on additionne net_amount_eur, jamais le
--        produit quantité × prix ;
--      - A-2003 et A-6002 (référence d'origine absente ou introuvable) :
--        ce sont quand même des avoirs émis, ils réduisent le CA ; la
--        référence ne compte pas ici (question 3.5) ;
--      - aucun avoir interne dans les données : la colonne interne ne
--        contient que des factures.
--
-- Raisonnement :
--   - Une seule lecture de la table : chaque mesure a sa condition dans
--     un SUM(IF(condition, montant, 0)). Quatre SUM(IF()) dans un SELECT,
--     c'est normal : c'est l'intérêt de la technique.
--   - Les avoirs sont déjà négatifs : une simple somme les retranche.
--     Ne pas les soustraire une deuxième fois.
--   - is_intercompany IS FALSE plutôt que NOT is_intercompany : le sens
--     est le même sauf pour NULL, qui ne tombe alors ni dans interne ni
--     dans externe ; l'écart de contrôle le révélerait.
--   - Le CA consolidé est calculé directement, avec sa propre condition,
--     et non par différence (total - interne) : par différence, le
--     contrôle vaudrait 0 par construction et ne vérifierait rien. Deux
--     calculs indépendants qui retombent sur le même total, c'est un
--     vrai contrôle.
--   - Les montants sont en FLOAT : une somme peut donner 6342.999999…
--     On arrondit l'écart à 2 décimales avant de le comparer à 0.
--   - Contrôle écrit comme un écart (qui doit valoir 0) plutôt qu'un
--     booléen : en cas d'erreur, l'écart dit aussi de combien.
-- ---------------------------------------------------------------------

WITH entity_amounts AS (
    SELECT
        sl.entity_id,
        SUM(sl.net_amount_eur)                                       AS total_amount_eur,
        SUM(IF(sl.is_intercompany, sl.net_amount_eur, 0))            AS intercompany_amount_eur,
        SUM(IF(sl.is_intercompany IS FALSE
               AND sl.document_type = 'credit_note', sl.net_amount_eur, 0)) AS external_credit_note_amount_eur,
        SUM(IF(sl.is_intercompany IS FALSE, sl.net_amount_eur, 0))   AS consolidated_revenue_amount_eur
    FROM sql_practice.sales_lines AS sl
    GROUP BY
        sl.entity_id
)

SELECT
    ea.entity_id,
    ea.total_amount_eur,
    ea.intercompany_amount_eur,
    ea.external_credit_note_amount_eur,
    ea.consolidated_revenue_amount_eur,
    ROUND(ea.total_amount_eur
          - ea.intercompany_amount_eur
          - ea.consolidated_revenue_amount_eur, 2) AS control_gap_amount_eur
FROM entity_amounts AS ea
ORDER BY
    ea.entity_id

-- ---------------------------------------------------------------------
-- Résultat obtenu : 2 lignes, conformes au tableau de la prédiction ;
--   control_gap_amount_eur = 0 pour FR et DE.
-- Écart avec la prédiction : aucun.
--
-- Prolongement : un avoir interne (retour de DE à FR, ou correction du
--   prix de transfert) s'élimine comme la facture interne qu'il corrige :
--   la règle porte sur le client, pas sur le type de document. Un avoir
--   interne de -144 baisserait total et interne de 144 ; CA consolidé et
--   avoirs externes inchangés ; écart toujours 0 (partition interne /
--   externe). Il ne doit pas entrer dans un taux d'avoirs clients.
--
-- Ce que je retiens :
--   - SUM(IF(condition, valeur, 0)) : plusieurs mesures, chacune avec sa
--     condition, en une seule lecture et un seul GROUP BY.
--   - Les avoirs sont signés négativement : une somme simple donne
--     directement le net.
--   - Un contrôle n'a de valeur que si ses termes sont calculés
--     indépendamment ; une colonne obtenue par différence rend le
--     contrôle tautologique.
--   - IS FALSE / IS TRUE pour un booléen qui pourrait être NULL.
--   - FLOAT : arrondir avant de comparer à 0.
--   - L'écart (montant) est plus parlant qu'un booléen de contrôle.
