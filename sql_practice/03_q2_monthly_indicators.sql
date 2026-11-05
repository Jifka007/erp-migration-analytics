-- =====================================================================
-- Thème 3 – Agrégations conditionnelles
-- Question 3.2 – Plusieurs indicateurs par mois
-- =====================================================================
-- Énoncé : une ligne par filiale et par mois, avec : le nombre de
--   factures (numéros distincts) et le nombre d'avoirs aux clients
--   extérieurs, le CA consolidé, et le taux d'avoirs (montant des avoirs
--   ÷ montant des factures, clients extérieurs, positif, entre 0 et 1).
--   Puis, par filiale, le taux d'avoirs sur les deux mois calculé de deux
--   façons : la moyenne des taux mensuels, et le rapport des sommes.
--   Expliquer l'écart et dire lequel est juste.
-- Tables : sql_practice.sales_lines
-- Date de référence : 2026-09-30
-- ---------------------------------------------------------------------
-- Grain du résultat : une ligne = une filiale.
--   Étape 1 (monthly_entity_indicators) : une ligne = une filiale et un
--     mois (4 lignes : FR et DE, août et septembre 2026).
--
-- Prédiction de contrôle (avant d'exécuter) :
--   1. Nombre de lignes : 4 dans la CTE, 2 dans le résultat final.
--   2. Totaux de contrôle (clients extérieurs uniquement) :
--      | Filiale | Mois  | Factures | Avoirs | CA consolidé | Factures € | Avoirs € | Taux   |
--      | DE      | août  | 2        | 0      | 3250.00      | 3250.00    |    0.00  | 0      |
--      | DE      | sept. | 2        | 2      | 3093.00      | 3397.50    | -304.50  | 0.0896 |
--      | FR      | août  | 2        | 1      | 3412.00      | 3520.00    | -108.00  | 0.0307 |
--      | FR      | sept. | 2        | 2      | 3680.00      | 3826.00    | -146.00  | 0.0382 |
--      Résultat final :
--      | Filiale | Moyenne des taux | Rapport des sommes        |
--      | DE      | 0.0448           | 304.50 / 6647.50 = 0.0458 |
--      | FR      | 0.0344           | 254.00 / 7346.00 = 0.0346 |
--   3. Cas limites :
--      - F-1001 et F-1004 ont deux lignes : sans DISTINCT, FR compterait
--        3 factures par mois ;
--      - F-1003, F-1006 et F-5005 (internes) : sans le filtre, FR
--        compterait aussi 3 factures, et les taux seraient faussés ;
--      - DE en août, aucun avoir : credit_note_count = 0 (COUNT renvoie
--        toujours un nombre) et taux = 0, pas NULL (SAFE_DIVIDE ne renvoie
--        NULL que si le dénominateur vaut 0) ;
--      - A-2002 (geste commercial, quantité 0) : compté comme avoir, son
--        montant de -96 entre dans le taux.
--
-- Raisonnement :
--   - Aucune colonne n'a besoin des ventes internes : on les écarte une
--     seule fois dans le WHERE, avant le GROUP BY. Les conditions des
--     mesures deviennent plus courtes.
--   - Compter des documents distincts sous condition :
--     COUNT(DISTINCT IF(condition, sl.invoice_number, NULL)).
--     COUNTIF compte des lignes, pas des valeurs distinctes. La valeur
--     gardée est ce qu'on compte (le numéro) : avec 1, DISTINCT ne
--     garderait qu'un seul 1 et le résultat vaudrait au plus 1. NULL (et
--     non 0) neutralise les lignes hors condition, car COUNT compterait
--     un 0.
--   - Taux positif : -SUM(...) plutôt que ABS(SUM(...)). ABS masquerait
--     un avoir saisi en positif par erreur ; le signe moins pose la règle
--     « les avoirs sont négatifs » et rend une anomalie visible.
--   - La CTE garde le numérateur et le dénominateur du taux
--     (credit_note_amount_eur, invoice_amount_eur) : le rapport des
--     sommes se calcule à partir d'eux, sans relire la table brute. Une
--     règle écrite une seule fois ne peut pas être oubliée une deuxième
--     fois (une première version relisait sales_lines sans le filtre des
--     ventes internes : 0.0271 au lieu de 0.0346 pour FR).
--   - Mois au premier jour : DATE_TRUNC(..., MONTH), répété dans le
--     GROUP BY (l'alias du SELECT n'est pas portable d'un moteur à
--     l'autre).
-- ---------------------------------------------------------------------

WITH monthly_entity_indicators AS (
    SELECT
        sl.entity_id,
        DATE_TRUNC(sl.invoice_date, MONTH)                               AS month_start_date,
        COUNT(DISTINCT IF(
            sl.document_type = 'invoice', sl.invoice_number, NULL))      AS invoice_count,
        COUNT(DISTINCT IF(
            sl.document_type = 'credit_note', sl.invoice_number, NULL))  AS credit_note_count,
        SUM(sl.net_amount_eur)                                           AS consolidated_revenue_amount_eur,
        SUM(IF(sl.document_type = 'invoice', sl.net_amount_eur, 0))      AS invoice_amount_eur,
        SUM(IF(sl.document_type = 'credit_note', sl.net_amount_eur, 0))  AS credit_note_amount_eur,
        SAFE_DIVIDE(
            -SUM(IF(sl.document_type = 'credit_note', sl.net_amount_eur, 0)),
            SUM(IF(sl.document_type = 'invoice', sl.net_amount_eur, 0))) AS credit_note_rate
    FROM sql_practice.sales_lines AS sl
    WHERE sl.is_intercompany IS FALSE
    GROUP BY
        sl.entity_id,
        DATE_TRUNC(sl.invoice_date, MONTH)
)

-- Taux d'avoirs par filiale sur les deux mois, de deux façons :
-- la moyenne des taux mensuels, et le rapport des sommes.
SELECT
    mei.entity_id,
    AVG(mei.credit_note_rate)                                                  AS avg_monthly_credit_note_rate,
    SAFE_DIVIDE(-SUM(mei.credit_note_amount_eur), SUM(mei.invoice_amount_eur)) AS credit_note_rate
FROM monthly_entity_indicators AS mei
GROUP BY
    mei.entity_id
ORDER BY
    mei.entity_id

-- ---------------------------------------------------------------------
-- Résultat obtenu : CTE conforme au tableau (4 lignes) ; résultat final
--   DE 0.0448 / 0.0458, FR 0.0344 / 0.0346.
-- Écart avec la prédiction : aucun.
--
-- Pourquoi les deux taux diffèrent : la moyenne arithmétique donne le
--   même poids à chaque mois ; le rapport des sommes pondère chaque taux
--   mensuel par son dénominateur (le montant facturé) :
--   Σa / Σb = Σ (b_i / Σb) × (a_i / b_i).
--   Chez DE, septembre a à la fois plus de ventes (3397.50 contre 3250)
--   et le taux le plus élevé : la pondération le favorise, le rapport des
--   sommes passe au-dessus de la moyenne. À montants facturés égaux, les
--   deux calculs coïncideraient.
--   Le juste est le rapport des sommes : c'est la définition du taux sur
--   la période.
--
-- Ce que je retiens :
--   - Un filtre utile à toutes les mesures va dans le WHERE, une fois.
--   - COUNT(DISTINCT IF(condition, identifiant, NULL)) pour compter des
--     documents distincts sous condition ; la valeur gardée est
--     l'identifiant de ce qu'on compte, et NULL (pas 0) hors condition.
--   - COUNT renvoie 0, jamais NULL ; SAFE_DIVIDE renvoie NULL seulement
--     si le dénominateur vaut 0.
--   - -SUM plutôt que ABS : on pose la règle de signe au lieu de la
--     masquer.
--   - Un taux ne s'additionne pas et ne se moyenne pas : on garde
--     numérateur et dénominateur, et on refait le rapport au niveau
--     voulu (dbt : stocker les deux ; Power BI : DIVIDE(SUM, SUM), jamais
--     AVERAGE d'un taux).
--   - Calculer à partir de la CTE plutôt que relire la table brute : une
--     règle écrite une seule fois.
