# Budget

*Rédigé en phase 1 (conception des sources), tâche 1.5, octobre 2026.*

Le budget est l'objectif de chiffre d'affaires que la finance fixe pour chaque filiale, chaque gamme et chaque mois. Il est saisi dans Google Sheets et alimente `fct_budget` (document 01, section 1), pour mesurer l'**écart au budget** (document 01, section 2).

## 1. Ce qu'on simule, et pourquoi

**Une feuille Google Sheets saisie par la finance, au format « large »** : une ligne par filiale et par gamme, un mois par colonne, un onglet par année *(pratique courante : c'est ainsi qu'une finance lit et saisit un budget)*. Un budget au format « long » (une ligne par filiale, gamme et mois) serait plus simple à charger, mais personne ne le saisit ainsi.

**Ce que ça change pour la chaîne** : `fct_budget` a une ligne par filiale, gamme et mois. La staging doit donc **dépivoter** la feuille : transformer les douze colonnes de mois en douze lignes (`UNPIVOT` dans BigQuery). C'est une transformation classique, testée par un contrôle simple : le total de l'année avant et après dépivotage doit être le même.

## 2. La mise en page

Un onglet par année : `Budget 2024`, `Budget 2025`, `Budget 2026`.

| Filiale | Gamme | Jan | Fév | Mar | … | Déc | Total |
| --- | --- | --- | --- | --- | --- | --- | --- |
| France | Chaussures | 430 000 | 440 000 | 480 000 | … | 410 000 | 5 400 000 |
| France | Antichute | 280 000 | 285 000 | 310 000 | … | 265 000 | 3 500 000 |
| France | Gants | 150 000 | 155 000 | 165 000 | … | 190 000 | 2 000 000 |
| Allemagne | Chaussures | … | … | … | … | … | … |

- Les montants indiqués sont à l'échelle de développement du projet (1/10e) : la France pèse environ 28 % des 39 M€ du groupe.
- **Le budget porte sur le CA consolidé** : les ventes aux clients extérieurs seulement, hors ventes entre filiales. Le budget d'une plateforme ne contient donc que ses ventes à ses propres clients ; ce qu'elle vend aux autres entités est budgété chez elles.
- Les montants sont en **euros**, pour toutes les filiales : la finance budgète le groupe dans sa devise *(hypothèse)*. Ils se comparent au CA converti au taux moyen du mois. Pour une filiale hors zone euro (Chine, Émirats, Brésil), l'écart au budget contient donc aussi un **effet de change** : si le yuan baisse, la Chine paraît sous son budget sans avoir vendu moins. Le lire aux taux du budget est une extension (document 01, section 8).
- La colonne `Total` est une formule de la feuille : elle n'est pas chargée, elle sert de contrôle.
- Les filiales et les gammes sont écrites **en toutes lettres**, comme les voit la finance (« France », « Gants »). Une table de correspondance les ramène à `entity_id` et `product_line_id`.

## 3. Le périmètre : le piège du Brésil

**On compare toujours le réalisé et le budget sur le même périmètre.** Le Brésil n'est entré dans le groupe que le 1er janvier 2026 :

- les onglets 2024 et 2025 ne contiennent **pas de lignes pour le Brésil** ;
- l'onglet 2026 contient le Brésil depuis janvier : le budget a été **révisé** après le rachat *(hypothèse)*.

Si le budget 2026 avait été voté sans le Brésil, le groupe paraîtrait au-dessus de son budget grâce au seul rachat. C'est pourquoi l'écart au budget se lit aussi **hors Brésil**, à périmètre constant.

## 4. Les pièges d'une feuille saisie à la main, et leur traitement

| Piège | Traitement dans la staging |
| --- | --- |
| Format large, un mois par colonne | Dépivotage ; contrôle du total annuel avant et après |
| Noms de filiales et de gammes en toutes lettres, parfois mal orthographiés (« Allemangne ») | Table de correspondance, test : chaque ligne trouve une filiale et une gamme |
| Cellules vides (mois non budgétés) | Un mois vide vaut zéro **et** est signalé : un budget manquant n'est pas un budget nul |
| Nombres saisis en texte, avec des espaces (`285 000`) | Conversion numérique, test de valeur non nulle |
| Ligne `Total` ou ligne de sous-total ajoutée par la finance | Exclue, et utilisée comme contrôle |
| Onglet renommé ou ajouté en cours d'année (`Budget 2026 révisé`) | La liste des onglets attendus est fixée ; un onglet inattendu fait échouer le chargement avec un message clair |

Les taux de ces défauts sont fixés en tâche 1.6 (`config/delta_plus/defects.yml`).

**Une seule version par année.** Quand la finance révise le budget (pour ajouter le Brésil en 2026, par exemple), elle remplace les chiffres dans l'onglet de l'année. Le projet ne garde donc que la dernière version ; suivre les versions successives d'un budget (initial, révisé) est une extension.

## 5. Le calibrage

Le budget est généré à partir de l'historique, avec une ambition de croissance par filiale et par gamme *(hypothèse)*. Il ne reprend aucun chiffre réel de Delta Plus, qui ne publie pas de budget. Il ne contient pas non plus les histoires cachées : un budget « juste » rendrait les écarts trop faciles à lire, un budget fixé avant les événements de la période les fait au contraire apparaître, comme en vrai.
