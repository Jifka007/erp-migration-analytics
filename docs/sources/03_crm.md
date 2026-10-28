# CRM

*Rédigé en phase 1 (conception des sources), tâche 1.4, octobre 2026. Un exemple complet et valide est dans [`03_crm_example.json`](03_crm_example.json).*

Le CRM est l'outil des commerciaux. Il enregistre les comptes qu'ils suivent (clients et prospects), leurs contacts, leurs visites et leurs opportunités. Chez Delta Plus, c'est Efficy : environ 500 commerciaux, plus de 106 000 clients et prospects *(Delta Plus, référence de l'éditeur)*, pour un peu plus de 10 000 clients dans les ERP *(Delta Plus, document d'enregistrement universel 2025)*. La plupart des comptes du CRM ne sont donc pas des clients.

## 1. Ce qu'on simule, et pourquoi

**Des réponses d'API enregistrées en fichiers JSON** *(pratique courante)*. Un CRM en SaaS s'interroge par une API, qui renvoie des pages de résultats : une enveloppe avec ses métadonnées, puis une liste de comptes. Le projet ne peut pas héberger une API ; il simule donc ce qu'une extraction automatique produirait : un fichier par page, posé dans un stockage lisible par Airbyte (emplacement choisi en phase 3).

**Pourquoi ce format** : c'est la réponse du projet au « NoSQL » de l'offre de Delta Plus. Le document est **vraiment imbriqué** : un compte contient des listes (contacts, visites, opportunités), et certaines de ces listes en contiennent d'autres (les contacts d'une visite, les lignes d'une opportunité). Il faut deux niveaux de dépliage (`UNNEST`) pour arriver aux lignes d'opportunité.

**Le rôle dans le cœur** : uniquement le **rapprochement des clients** entre le CRM et les deux ERP (section 4). L'analyse commerciale (les opportunités qui deviennent des commandes) est une extension. Les visites et les opportunités sont quand même générées : ce sont elles qui rendent le document imbriqué.

**Le périmètre** : les cinq entités qui utilisent le CRM. Le Brésil, racheté avec ses propres outils, n'y est pas encore *(hypothèse cohérente avec le reste du projet)*.

## 2. L'enveloppe d'une page

| Champ | Type | Signification |
| --- | --- | --- |
| `page` | entier | Numéro de la page |
| `page_size` | entier | Nombre de comptes par page |
| `total_items` | entier | Nombre total de comptes modifiés depuis `modified_since` |
| `has_more` | booléen | Vrai s'il reste des pages |
| `extracted_at` | texte (horodatage ISO 8601) | Date et heure de l'extraction |
| `modified_since` | texte (horodatage ISO 8601) | L'extraction ne renvoie que les comptes modifiés depuis cette date |
| `items` | liste | Les comptes |

**La première extraction est complète** (`modified_since` vide), les suivantes sont **incrémentales** : chaque nuit, seuls les comptes modifiés depuis la veille sont extraits. Un même compte apparaît donc dans plusieurs fichiers, une fois par modification. La staging ne garde, pour chaque `account_id`, que la version la plus récente (`updated_at` le plus grand). Additionner les fichiers compterait un compte plusieurs fois. Un compte supprimé n'apparaît jamais dans une extraction incrémentale : c'est pourquoi le CRM fusionne ou archive les comptes au lieu de les effacer, et les signale par `status`.

## 3. Le document compte

### Le compte

| Champ | Type | Toujours présent | Signification | Nom cible |
| --- | --- | --- | --- | --- |
| `account_id` | texte | oui | Identifiant du compte dans le CRM (`ACC-004512`), **stable** : c'est la clé du compte | `crm_account_id` |
| `account_type` | texte | non | `customer` ou `prospect` ; absent sur certains comptes anciens | `crm_account_type` |
| `name` | texte | oui | Raison sociale, telle que saisie (majuscules, formes juridiques, accents variables) | `crm_account_name` |
| `tax_id` | texte | non | Identifiant officiel de l'entreprise : TVA intracommunautaire en Europe, identifiant national ailleurs ; formats variables, souvent vide | `tax_id` |
| `sales_entity` | texte | oui | Entité du groupe qui suit le compte (`FR`, `DE`…) | `entity_id` |
| `segment` | texte | non | Segment, **en texte libre** (« Négoce BTP », « builders merchant », « négoce ») | `customer_segment_id` (par correspondance) |
| `erp_customer_code` | texte | non | Code client de l'ERP, écrit par l'interface ERP → CRM ; vide pour un prospect, parfois ancien (voir la section 4) | sert à `map_customers` |
| `address` | objet | oui | `street`, `postal_code`, `city`, `country` (code ISO ou nom du pays en toutes lettres) | `postal_code`, `city`, `country_code` |
| `sales_rep` | objet | oui | `rep_id`, `name` : le commercial responsable | `sales_rep_id` |
| `created_at`, `updated_at` | texte (horodatage) | oui | Création et dernière modification du compte | `created_at`, `updated_at` |
| `status` | texte | non | `active` (par défaut), `archived`, ou `merged` quand le compte a été fusionné avec un doublon | `crm_account_status` |
| `merged_into` | texte | non | Pour un compte fusionné : le compte qui le remplace | `merged_into_account_id` |
| `contacts` | liste | oui (parfois vide) | Les interlocuteurs | voir ci-dessous |
| `visits` | liste | oui (parfois vide) | Les visites et appels | voir ci-dessous |
| `opportunities` | liste | oui (parfois vide) | Les ventes en préparation | voir ci-dessous |

### Les listes imbriquées

| Liste | Champs | Particularités |
| --- | --- | --- |
| `contacts` | `contact_id`, `first_name`, `last_name`, `job_title`, `email`, `phone` | `email` et `phone` souvent absents |
| `visits` | `visit_id`, `date`, `type` (`visite`, `téléphone`, `salon`), `contact_ids` (**liste**), `product_lines_discussed` (**liste**, parfois vide), `notes` | La date est tantôt `YYYY-MM-DD`, tantôt `DD/MM/YYYY`, selon l'écran de saisie ; `notes` souvent absent |
| `opportunities` | `opportunity_id`, `created_date`, `stage` (`qualification`, `proposition`, `négociation`, `gagnée`, `perdue`), `expected_close_date`, `estimated_amount`, `currency`, `lines` (**liste**) | Le montant est parfois un nombre, parfois un texte au format local (`"12 000,00"`) |
| `opportunities[].lines` | `product_line`, `product_family`, `quantity` | `product_family` en libellé, parfois absent |

Ces irrégularités sont normales dans un CRM : des champs facultatifs, de la saisie libre, plusieurs écrans pour la même information. Le code ERP lui-même peut être mal recopié : sans les zéros de tête (`1042` pour `00001042`), ou avec des espaces. Leurs taux sont fixés en tâche 1.6 (`defects.yml`).

## 4. Le rapprochement avec les ERP

### Comment le code ERP arrive dans le CRM

L'ERP est la référence des clients. Une **interface** crée ou met à jour chaque nuit les clients dans le CRM et y écrit leur code ERP. Les prospects naissent dans le CRM ; quand l'un d'eux commande, le client est créé dans l'ERP et l'interface renvoie le code au CRM *(pratique courante ; le fonctionnement réel entre Efficy et les ERP de Delta Plus n'est pas public : question pour l'entretien)*.

Trois situations rendent ce code incomplet ou faux :

- **des comptes créés à la main** dans le CRM, sans code, ou en double ;
- **des codes jamais renvoyés** par l'interface ;
- **la migration** : pour la France et l'Allemagne, l'interface n'est rebranchée sur M3 que progressivement *(hypothèse)*. Une partie des comptes garde l'**ancien** code (`00001042`), d'autres ont le nouveau (`FR1042`).

### La table de correspondance des comptes

Le rapprochement se fait en deux temps. D'abord, `map_customers` relie les clients des deux ERP entre eux, par l'ancien code repris dans M3 (`OKOLDC`), et leur donne un identifiant unifié, `customer_id` (document 01, section 4). Ensuite, `map_crm_accounts` relie chaque compte du CRM à ces clients unifiés. Un code ERP du CRM, qu'il soit ancien (`00001042`) ou nouveau (`FR1042`), retombe donc sur le même client.

`map_crm_accounts` a une ligne par couple « compte du CRM, client » : un compte peut correspondre à plusieurs clients (un grand groupe du BTP, un seul compte dans le CRM, plusieurs comptes clients dans l'ERP, un par agence), et un client à plusieurs comptes (des doublons du CRM).

| Colonne | Contenu |
| --- | --- |
| `crm_account_id` | Le compte du CRM |
| `customer_id` | Le client unifié (vide si `unmatched`) |
| `entity_id` | L'entité du groupe |
| `match_status` | `certain`, `probable` ou `unmatched` |
| `match_rule` | La règle qui a produit le rapprochement |

| Statut | Règle | Exemple |
| --- | --- | --- |
| `certain` | `erp_customer_code`, une fois normalisé (zéros de tête rétablis, espaces retirés), existe dans un des deux ERP pour l'entité du compte | `ACC-004512` a le code `00001042`, qui est l'ancien code de `FR1042` : même client unifié |
| `probable` | Pas de code, ou un code inconnu, mais le même identifiant officiel, la même raison sociale normalisée et le même code postal | « DUPONT NEGOCE SAS » et « Dupont Négoce », même TVA, même code postal |
| `unmatched` | Rien trouvé | Un prospect, ou un client non rapproché |

**Seuls les clients extérieurs sont rapprochés** : les clients internes (sociétés du groupe) n'ont pas de compte dans le CRM.

**Le segment vient de l'ERP.** Le CRM a son propre segment, en texte libre ; l'ERP est la référence des clients, donc `dim_customer` prend le segment de l'ERP. Le segment du CRM ne sert qu'à un contrôle : un écart entre les deux est signalé, et il dit si la nouvelle segmentation est bien appliquée par les commerciaux.

**La raison sociale normalisée** : en minuscules, sans accents, sans ponctuation ni forme juridique (`sas`, `sarl`, `gmbh`, `ltd`…). C'est une règle de staging, testée sur des cas connus.

**Un compte `unmatched` n'est pas forcément une erreur.** Un prospect (`account_type = prospect`) n'a pas encore de client dans l'ERP : c'est normal. Seuls les comptes `customer` non rapprochés sont des anomalies, signalées sur la page qualité. Les comptes sans `account_type` sont classés selon leur historique : ceux qui ont une opportunité gagnée sont traités comme des clients.

| Règle | Source | À valider avec |
| --- | --- | --- |
| L'ERP est la référence des clients, le CRM la référence des prospects | Pratique courante | Direction commerciale, direction informatique |
| Rapprochement par code ERP, puis par identifiant officiel, raison sociale normalisée et code postal | Pratique courante | Direction informatique |
| Un compte peut correspondre à plusieurs clients de l'ERP | Pratique courante | Direction commerciale |
| Seuls les comptes clients non rapprochés sont des anomalies | Hypothèse | Direction informatique |

## 5. Les volumes

Le rapport entre comptes du CRM et clients de l'ERP reprend celui de Delta Plus, environ 10 pour 1. Au 1/1, environ 100 000 comptes pour les 10 000 clients du référentiel ; au 1/10e, environ 10 000 comptes. Les prospects ont peu de visites et rarement des opportunités ; les clients actifs en ont davantage *(hypothèse)*.

## 6. Ce qui n'est pas dans ce document

- Les taux des irrégularités (champs absents, dates et montants mal formatés, segments en texte libre, codes ERP anciens ou faux, doublons de comptes) : tâche 1.6, `config/delta_plus/defects.yml`.
- L'analyse des opportunités (conversion en commandes) : extension.

## Sources

- [Finopsys, référence CRM Efficy chez Delta Plus](https://www.finopsys.fr/finopsys/references/delta-plus/)
- [Delta Plus, document d'enregistrement universel 2025 (plus de 10 000 clients)](https://financialfilings.com/filings/delta-plus-group/annual-report-esef/2026/37970547/)
