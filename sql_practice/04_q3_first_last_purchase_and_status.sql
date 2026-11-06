-- =====================================================================
-- Thème 4 – Dates et fenêtres glissantes
-- Question 4.3 – Premier et dernier achat, clients nouveaux et perdus
-- =====================================================================
-- Énoncé : pour chaque client, à la date de référence : la date du
--   premier et du dernier achat, le nombre de jours depuis le dernier
--   achat, et un statut :
--     - 'new' : premier achat dans les 12 mois glissants (après le
--       2025-09-30) ;
--     - 'active' : client plus ancien, avec un achat dans ces 12 mois ;
--     - 'lost' : aucun achat dans ces 12 mois.
--   Puis le nombre de clients par filiale et par statut.
-- Tables : sql_practice.customer_invoices
-- Date de référence : 2026-09-30 (fin de journée)
-- ---------------------------------------------------------------------
-- Grain du résultat : une ligne = une filiale et un statut (6 lignes).
--   Étapes :
--     - parameters, active_window : une ligne, la date de référence et le
--       début de la fenêtre (2025-10-01) ;
--     - customer_statuses : une ligne = un client (7).
--
-- Prédiction de contrôle (avant d'exécuter) :
--   1. Nombre de lignes : 7 clients ; 6 lignes au résultat final.
--   2. Totaux de contrôle :
--      | Client  | Premier    | Dernier    | Jours | Factures | Statut |
--      | FR-C001 | 2025-03-14 | 2026-07-22 |    70 | 4        | active |
--      | FR-C002 | 2024-11-20 | 2025-06-02 |   485 | 2        | lost   |
--      | FR-C003 | 2026-03-03 | 2026-09-30 |     0 | 3        | new    |
--      | FR-C004 | 2025-10-01 | 2025-10-01 |   364 | 1        | new    |
--      | DE-C010 | 2025-01-15 | 2026-05-11 |   142 | 3        | active |
--      | DE-C011 | 2025-09-30 | 2025-09-30 |   365 | 1        | lost   |
--      | DE-C012 | 2026-06-18 | 2026-08-04 |    57 | 2        | new    |
--      Résultat final : FR active 1, lost 1, new 2 ; DE active 1, lost 1,
--      new 1 ; total 7 clients.
--   3. Cas limites :
--      - FR-C004 : premier achat le jour même du début de la fenêtre,
--        borne incluse : new ;
--      - DE-C011 : seul achat un jour avant la fenêtre : lost ;
--      - FR-C003 : achat le jour de la référence, 0 jour : inclus (<=).
--
-- Raisonnement :
--   - Le statut est une propriété du client : grain client, MIN et MAX
--     des dates d'achat jusqu'à la date de référence (WHERE <=, une
--     facture postérieure fausserait le dernier achat).
--   - Début de fenêtre calculé une fois depuis la date de référence
--     (active_window) : 1er jour du mois de référence - 11 mois, valable
--     car la date de référence est une fin de mois (sinon : DATE_SUB(
--     date, 12 mois) + 1 jour).
--   - Ordre du CASE : le premier WHEN vrai l'emporte. D'abord 'lost'
--     (dernier achat avant la fenêtre) ; parmi les restants, tous ont un
--     achat dans la fenêtre : 'new' si le premier achat y est aussi,
--     sinon 'active'. Une première version testait MIN < W AND MIN >= W,
--     toujours faux : l'ELSE 'other status' l'a révélé.
--   - Les colonnes de parameters sont des constantes : dans le GROUP BY,
--     elles ne changent pas le grain (pas de MAX() pour les faire passer).
--   - COUNT(*) : on compte les lignes (les factures) du groupe.
-- ---------------------------------------------------------------------

WITH parameters AS (
    SELECT
        DATE '2026-09-30' AS reference_date
),

active_window AS (
    SELECT
        p.reference_date,
        DATE_SUB(DATE_TRUNC(p.reference_date, MONTH), INTERVAL 11 MONTH) AS active_window_start_date
    FROM parameters AS p
),

customer_statuses AS (
    SELECT
        ci.entity_id,
        ci.customer_id,
        MIN(ci.invoice_date)                                    AS first_invoice_date,
        MAX(ci.invoice_date)                                    AS last_invoice_date,
        DATE_DIFF(aw.reference_date, MAX(ci.invoice_date), DAY) AS days_since_last_invoice,
        COUNT(*)                                                AS invoice_count,
        CASE
            WHEN MAX(ci.invoice_date) <  aw.active_window_start_date THEN 'lost'
            WHEN MIN(ci.invoice_date) >= aw.active_window_start_date THEN 'new'
            ELSE 'active'
        END                                                     AS customer_status
    FROM sql_practice.customer_invoices AS ci
    CROSS JOIN active_window AS aw
    WHERE ci.invoice_date <= aw.reference_date
    GROUP BY
        ci.entity_id,
        ci.customer_id,
        aw.reference_date,
        aw.active_window_start_date
)

SELECT
    cs.entity_id,
    cs.customer_status,
    COUNT(*) AS customer_count
FROM customer_statuses AS cs
GROUP BY
    cs.entity_id,
    cs.customer_status
ORDER BY
    cs.entity_id,
    cs.customer_status

-- Variante en format large (une ligne par filiale, un statut absent
-- vaut 0 au lieu de disparaître) :
--   SELECT
--       cs.entity_id,
--       COUNTIF(cs.customer_status = 'new')    AS new_customer_count,
--       COUNTIF(cs.customer_status = 'active') AS active_customer_count,
--       COUNTIF(cs.customer_status = 'lost')   AS lost_customer_count
--   FROM customer_statuses AS cs
--   GROUP BY
--       cs.entity_id

-- ---------------------------------------------------------------------
-- Résultat obtenu : customer_statuses conforme au tableau (7 clients) ;
--   résultat final DE active 1, lost 1, new 1 ; FR active 1, lost 1,
--   new 2.
-- Écart avec la prédiction : aucun.
--
-- Ce que je retiens :
--   - Premier et dernier achat : MIN et MAX au grain client, jusqu'à la
--     date de référence ; DATE_DIFF(référence, dernier achat, DAY).
--   - Un CASE se lit dans l'ordre : écarter d'abord un cas, puis les
--     conditions suivantes se simplifient.
--   - Toujours un ELSE visible ('other status') pendant la mise au point :
--     une condition impossible se voit au lieu de donner NULL.
--   - Sans ORDER BY, l'ordre des lignes n'est pas garanti.
--   - Format long : une catégorie sans ligne disparaît (comme un mois sans
--     facture en 4.1) ; format large avec COUNTIF : elle vaut 0.
--   - Nommer la mesure par ce qu'elle compte : customer_count.
