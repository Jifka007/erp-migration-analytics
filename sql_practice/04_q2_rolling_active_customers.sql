-- =====================================================================
-- Thème 4 – Dates et fenêtres glissantes
-- Question 4.2 – Les clients actifs sur 12 mois glissants
-- =====================================================================
-- Énoncé : pour chaque filiale et chaque mois de janvier à septembre 2026,
--   le nombre de clients actifs : ceux qui ont au moins une facture dans
--   les 12 mois qui se terminent le dernier jour du mois (fenêtre
--   ]fin du mois - 12 mois ; fin du mois]). Exemple : pour mars 2026, du
--   1er avril 2025 au 31 mars 2026 inclus.
-- Tables : sql_practice.customer_invoices, sql_practice.entities
-- Date de référence : 2026-09-30 (fin de journée)
-- ---------------------------------------------------------------------
-- Grain du résultat : une ligne = une filiale et un mois (18 lignes).
--   Étapes :
--     - months, entity_months : le squelette, comme en 4.1 (18 lignes) ;
--     - month_windows : une ligne = une filiale et un mois, avec les
--       bornes de sa fenêtre de 12 mois ;
--     - jointure : une ligne = une fenêtre et une facture qui y tombe
--       (fan-out voulu : une facture compte pour jusqu'à 12 mois) ;
--     - GROUP BY : retour au grain filiale × mois.
--
-- Méthode, en deux temps :
--   - Étape A, à une seule date (2026-09-30) : un client est actif si son
--     dernier achat est dans la fenêtre ; FR 3, DE 2.
--   - Étape B, mois par mois : chaque ligne du squelette joue le rôle
--     d'une date de référence ; la jointure « refait le compte » pour les
--     18 lignes d'un coup.
--
-- Prédiction de contrôle (avant d'exécuter) :
--   1. Nombre de lignes : 18.
--   2. Totaux de contrôle :
--      | Mois 2026 | janv | févr | mars | avr | mai | juin | juil | août | sept |
--      | FR        | 3    | 3    | 4    | 4   | 4   | 3    | 3    | 3    | 3    |
--      | DE        | 2    | 2    | 2    | 2   | 2   | 3    | 3    | 3    | 2    |
--      - FR mars : FR-C003 fait son premier achat ;
--      - FR juin : FR-C002 sort (dernier achat le 2025-06-02, fenêtre au
--        2025-07-01) ;
--      - DE juin : DE-C012 arrive ;
--      - DE sept : DE-C011 sort (2025-09-30, un jour avant la fenêtre).
--   3. Cas limites :
--      - FR-C004 (seul achat le 2025-10-01) : actif en septembre 2026, la
--        borne de début est incluse ;
--      - DE-C011 (seul achat le 2025-09-30) : actif en août, perdu en
--        septembre ;
--      - FR-C001, FR-C003 : plusieurs factures dans une même fenêtre,
--        comptés une fois (COUNT DISTINCT).
--
-- Raisonnement :
--   - En 4.1, une facture appartient à un mois : jointure sur une
--     égalité. Ici, elle appartient à toutes les fenêtres qui la
--     contiennent : jointure sur un intervalle, À LA PLACE de l'égalité
--     (une première version gardait l'égalité de la 4.1 en plus : toutes
--     les conditions d'un ON doivent être vraies, on comptait alors les
--     clients du mois seul, FR mars = 1 au lieu de 4).
--   - Fenêtre du mois M : du 1er jour de M - 11 mois au dernier jour de M,
--     bornes incluses. Définition par mois calendaires, équivalente aux
--     12 mois glissants au jour près parce que chaque date de référence
--     est une fin de mois. Pour une date en milieu de mois, choisir et
--     écrire la définition : DATE_SUB(date, 12 mois) + 1 jour au jour près.
--   - « Actif » = au moins une facture dans la fenêtre : on compte les
--     clients distincts des factures de la fenêtre, sans calculer le
--     dernier achat de chaque client.
--   - LEFT JOIN depuis le squelette : un mois sans client actif
--     apparaîtrait avec 0 (COUNT DISTINCT d'une colonne NULL vaut 0).
--   - « Actif » dépend de la date : on le calcule dans la requête, on ne le
--     stocke pas dans la table des factures (mauvais grain, et faux dès
--     qu'on change de date).
-- ---------------------------------------------------------------------

WITH parameters AS (
    SELECT
        DATE '2026-01-01' AS period_start_date,
        DATE '2026-09-30' AS reference_date
),

months AS (
    SELECT
        month_start_date
    FROM parameters AS p
    CROSS JOIN UNNEST(GENERATE_DATE_ARRAY(p.period_start_date, DATE_TRUNC(p.reference_date, MONTH), INTERVAL 1 MONTH)) AS month_start_date
),

entity_months AS (
    SELECT
        e.entity_id,
        m.month_start_date
    FROM sql_practice.entities AS e
    CROSS JOIN months AS m
),

month_windows AS (
    SELECT
        em.entity_id,
        em.month_start_date,
        LAST_DAY(em.month_start_date)                    AS month_end_date,
        DATE_SUB(em.month_start_date, INTERVAL 11 MONTH) AS active_window_start_date
    FROM entity_months AS em
)

SELECT
    mw.entity_id,
    mw.month_start_date,
    COUNT(DISTINCT ci.customer_id) AS active_customer_count
FROM month_windows AS mw
LEFT JOIN sql_practice.customer_invoices AS ci
    ON  mw.entity_id = ci.entity_id
    AND ci.invoice_date BETWEEN mw.active_window_start_date AND mw.month_end_date
GROUP BY
    mw.entity_id,
    mw.month_start_date
ORDER BY
    mw.entity_id,
    mw.month_start_date

-- ---------------------------------------------------------------------
-- Résultat obtenu : conforme au tableau de la prédiction.
-- Écart avec la prédiction : aucun, après suppression de l'égalité de
--   mois héritée de la 4.1.
--
-- Ce que je retiens :
--   - Recette « à chaque date, combien de … sur les N derniers mois » :
--     1. le squelette : une ligne par date de référence ;
--     2. la fenêtre : début et fin pour chaque ligne du squelette ;
--     3. l'accroche : LEFT JOIN des faits dans la fenêtre (BETWEEN), puis
--        un comptage distinct.
--   - Jointure sur intervalle (non-equi join) : une ligne de faits peut
--     appartenir à plusieurs groupes ; ce fan-out est voulu, COUNT
--     DISTINCT le gère.
--   - Dans un ON, toutes les conditions s'additionnent (AND) : une
--     égalité oubliée annule la fenêtre.
--   - LAST_DAY(date) : dernier jour du mois ; DATE_SUB / DATE_ADD avec
--     INTERVAL n MONTH.
--   - Une fenêtre « 12 mois » se définit : mois calendaires ou au jour
--     près ; les deux coïncident en fin de mois.
--   - Une date en dur qui n'est qu'une autre date + 1 jour est un piège :
--     la calculer depuis la date de référence.
--   - Un statut qui dépend de la date (actif, perdu) se calcule, il ne se
--     stocke pas dans une table de faits.
