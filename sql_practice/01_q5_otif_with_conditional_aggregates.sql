
01 q5 otif with conditional aggregates · SQL
-- =====================================================================
-- Thème 1 – Jointures et grain
-- Question 1.5 (bonus) – L'OTIF par agrégat conditionnel
-- =====================================================================
-- Énoncé : recalculer is_otif avec un agrégat conditionnel : vrai si la
--   quantité expédiée au plus tard à la première date promise
--   (on_time_shipped_quantity) atteint la quantité commandée ; faux
--   sinon ; NULL si la première date promise est après la date de
--   référence. Pour chaque ligne de commande (12 lignes), calculer aussi
--   la quantité expédiée en retard (late_shipped_quantity) et le nombre
--   d'expéditions en retard (late_shipment_count).
--   Puis calculer l'OTIF des lignes promises en septembre 2026, le
--   comparer à celui de la question 1.3, expliquer pourquoi les deux
--   méthodes donnent le même taux sur ces données, et dans quel cas
--   elles divergeraient.
-- Tables : sql_practice.order_lines, sql_practice.deliveries
-- Date de référence : 2026-09-30
-- ---------------------------------------------------------------------
-- Grain du résultat : une seule ligne, le taux OTIF de septembre 2026.
--   Étape 1 (jointure, avant agrégation) : une ligne = une ligne de
--     commande associée à une de ses livraisons ; une ligne sans
--     livraison apparaît une fois, avec des NULL.
--   Étape 2 (order_line_shipments, après GROUP BY) : une ligne = une
--     ligne de commande, avec ses quantités à temps et en retard.
--   Étape 3 (order_line_otif_status) : une ligne = une ligne de
--     commande, avec is_otif.
--
-- Prédiction de contrôle (avant d'exécuter) :
--   1. Nombre de lignes :
--      - étape 1 : 14 (la jointure de la question 1.1 : toutes les
--        livraisons sont antérieures au 30 septembre, le filtre de date
--        n'en écarte aucune) ;
--      - étapes 2 et 3 : 12, une par ligne de commande ;
--      - résultat final : 1.
--   2. Totaux de contrôle :
--      - SUM(on_time_shipped_quantity) + SUM(late_shipped_quantity)
--        = SUM(total_shipped_quantity) = 630, la quantité expédiée totale
--        (question 1.2) : chaque expédition est soit à temps, soit en
--        retard, jamais les deux ;
--      - SUM(late_shipment_count) = 2 : L-931 (FR 45872/2, partie le
--        16/09 pour une promesse au 10/09) et L-925 (FR 45933/1, le 22/09
--        pour le 18/09). Donc 38 pièces en retard (8 + 30) et 592 à temps.
--   3. Cas limites :
--      - FR 45872/2 (fractionnée, une partie en retard) : 12 à temps,
--        8 en retard, 1 expédition en retard ; 12 < 20 commandées :
--        is_otif = FALSE ;
--      - FR 45940/1 (jamais expédiée) : 0, 0, 0 ; promesse du 20/09
--        passée et 0 < 10 : is_otif = FALSE ;
--      - FR 45940/2 (reliquat annulé) : 60 à temps < 80 commandées :
--        is_otif = FALSE ;
--      - DE 46012/1 (promise en octobre) : 0, 0, 0 ; promesse après la
--        date de référence : is_otif = NULL.
--   4. Taux de septembre : 5 / 10 = 0,5, les mêmes lignes OTIF qu'en
--      question 1.3 (5 TRUE, 5 FALSE, 2 NULL sur les 12 lignes).
--
-- Raisonnement :
--   - Pour classer une expédition à temps ou en retard, il faut comparer
--     shipped_date (deliveries) à first_promised_date (order_lines) :
--     on joint donc AVANT d'agréger, puis on revient au grain de la
--     ligne de commande avec un GROUP BY sur sa clé.
--   - Les colonnes de la ligne de commande utiles ensuite
--     (first_promised_date, ordered_quantity) vont dans le GROUP BY :
--     propres à la ligne, elles ne changent pas le grain. Pas de MIN()
--     pour les faire passer : ce serait une rustine.
--   - Le filtre de date de référence porte sur la table de droite d'un
--     LEFT JOIN : il va dans le ON (parameters est joint avant pour que
--     p.reference_date y soit visible), sinon les lignes jamais
--     expédiées disparaîtraient.
--   - Les agrégats conditionnels se calculent sur le détail des
--     expéditions, avant le regroupement : la condition porte sur la
--     date de CHAQUE expédition. Après le GROUP BY, ce détail est perdu.
--   - SUM(IF(condition, quantité, 0)) additionne seulement les
--     expéditions qui vérifient la condition ; COUNTIF(condition) les
--     compte. Pour une ligne sans livraison, shipped_date est NULL : la
--     condition vaut NULL, IF renvoie 0 et COUNTIF ne compte rien.
--   - total_shipped_quantity ne sert pas au calcul de l'OTIF : il est
--     gardé dans la CTE comme total de contrôle (à temps + en retard =
--     total).
--   - Ordre des tests dans le CASE : d'abord ce qui n'est pas jugeable
--     (promesse absente, ou postérieure au 30/09) → NULL ; ensuite la
--     condition de succès → TRUE ; tout le reste → FALSE. Une promesse
--     le 30/09 est jugeable (on se place en fin de journée) : > et non >=.
--   - Promesse absente : les deux conditions à temps / en retard valent
--     NULL, l'expédition ne serait comptée nulle part (le total de
--     contrôle le signalerait) ; is_otif = NULL, rien à juger.
--   - Annulation : faute de motif d'annulation dans ces données, règle
--     prudente, la quantité annulée compte comme non livrée. On compare
--     donc à ordered_quantity, sans retirer cancelled_quantity.
--   - En totalité : >= plutôt que =, une livraison en trop n'est pas un
--     échec.
--   - Le tri ne sert que dans le SELECT final ; ici le résultat tient en
--     une ligne, donc pas d'ORDER BY.
-- ---------------------------------------------------------------------
 
WITH parameters AS (
    SELECT
        DATE '2026-09-30' AS reference_date
),
 
order_line_shipments AS (
    SELECT
        ol.entity_id,
        ol.order_number,
        ol.order_line_number,
        ol.first_promised_date,
        ol.ordered_quantity,
        SUM(COALESCE(d.shipped_quantity, 0))                                     AS total_shipped_quantity,
        SUM(IF(d.shipped_date <= ol.first_promised_date, d.shipped_quantity, 0)) AS on_time_shipped_quantity,
        SUM(IF(d.shipped_date >  ol.first_promised_date, d.shipped_quantity, 0)) AS late_shipped_quantity,
        COUNTIF(d.shipped_date > ol.first_promised_date)                         AS late_shipment_count,
        p.reference_date
    FROM sql_practice.order_lines AS ol
    CROSS JOIN parameters AS p
    LEFT JOIN sql_practice.deliveries AS d
        ON  ol.entity_id         = d.entity_id
        AND ol.order_number      = d.order_number
        AND ol.order_line_number = d.order_line_number
        AND d.shipped_date       <= p.reference_date
    GROUP BY
        ol.entity_id,
        ol.order_number,
        ol.order_line_number,
        ol.first_promised_date,
        ol.ordered_quantity,
        p.reference_date
),
 
order_line_otif_status AS (
    SELECT
        ols.entity_id,
        ols.order_number,
        ols.order_line_number,
        ols.first_promised_date,
        ols.ordered_quantity,
        ols.on_time_shipped_quantity,
        ols.late_shipped_quantity,
        ols.late_shipment_count,
        CASE
            WHEN ols.first_promised_date IS NULL
                OR ols.first_promised_date > ols.reference_date THEN NULL
            WHEN ols.on_time_shipped_quantity >= ols.ordered_quantity THEN TRUE
            ELSE FALSE
        END AS is_otif
    FROM order_line_shipments AS ols
)
 
SELECT
    SAFE_DIVIDE(COUNTIF(olos.is_otif), COUNT(*)) AS otif_rate
FROM order_line_otif_status AS olos
WHERE olos.is_otif IS NOT NULL
    AND DATE_TRUNC(olos.first_promised_date, MONTH) = DATE '2026-09-01'
 
-- ---------------------------------------------------------------------
-- Résultat obtenu : otif_rate = 0.5.
--   Contrôles faits avec SELECT * sur chaque CTE : 12 lignes ;
--   on_time = 592, late = 38, total = 630 ; late_shipment_count = 2 ;
--   is_otif : 5 TRUE, 5 FALSE, 2 NULL ; cas limites conformes.
-- Écart avec la prédiction : aucun.
--
-- Comparaison avec la question 1.3 : même taux (0,5) et mêmes lignes
--   OTIF. La 1.3 teste « dernière expédition <= promesse ET total >=
--   commandé » ; la 1.5 teste « quantité expédiée à temps >= commandé ».
--   Sur ces données, aucune ligne n'a reçu de livraison en trop après sa
--   promesse : les deux tests disent la même chose.
--
-- Cas où les deux méthodes divergeraient : une ligne de 100 commandées,
--   100 expédiées à l'heure, puis 5 de plus en retard. 1.3 : dernière
--   expédition en retard → FALSE. 1.5 : 100 à temps >= 100 → TRUE. Toute
--   ligne OTIF selon la 1.3 l'est selon la 1.5 : le taux de la 1.5 n'est
--   jamais inférieur. La 1.5 suit la définition littérale de l'énoncé.
--
-- Ce que je retiens :
--   - Agrégats conditionnels : SUM(IF(condition, valeur, 0)) et
--     COUNTIF(condition) calculent, dans un même SELECT, des mesures avec
--     des conditions différentes. La condition porte sur le détail, avant
--     le GROUP BY ; une condition NULL compte comme fausse.
--   - Joindre puis agréger : quand le calcul compare des colonnes des
--     deux tables, on joint d'abord, puis on revient au grain voulu avec
--     un GROUP BY sur la clé (et les attributs propres à la ligne).
--   - Un filtre sur la table de droite d'un LEFT JOIN va dans le ON ou
--     dans une CTE, jamais dans le WHERE final.
--   - Décomposer une mesure complexe en mesures simples et additives
--     (à temps, en retard, nombre de retards), puis reconstruire
--     l'indicateur à la fin : on gagne des contrôles (les parties
--     retombent sur le total), du diagnostic (pourquoi une ligne échoue)
--     et des analyses réutilisables (OTIF en volume, suivi des retards).
--     Un taux ne s'additionne pas : on stocke numérateur et dénominateur.
--   - Une CTE peut garder des colonnes de contrôle (total_shipped_quantity)
--     même si le résultat final ne les utilise pas.
--   - Le tri (ORDER BY) ne se met que dans le SELECT final.
--   - Dans un CASE, on teste d'abord ce qui n'est pas jugeable (NULL),
--     y compris une date promise absente.
--   - Une règle métier qui dépend d'une donnée absente (qui a annulé ?)
--     se traite avec une règle prudente, documentée, signalée comme
--     limite.
--   - Convention : colonnes toujours préfixées par l'alias de leur table,
--     même quand le bloc ne lit qu'une table.
 
