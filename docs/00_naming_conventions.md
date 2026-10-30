# Conventions de nommage

*Rédigé en phase 1 (conception des sources), octobre 2026. Ce document s'applique à tout le dépôt : documents, configuration, tables, colonnes et Git.*

Un bon nom dit ce que contient l'objet, sans avoir à l'ouvrir. Les règles ci-dessous sont fixées avant d'écrire le code, pour ne jamais avoir à renommer ensuite.

## 1. Les règles générales

- **Tous les noms techniques sont en anglais et en `snake_case`** : minuscules, mots séparés par un tiret bas (`sales_lines`, pas `SalesLines` ni `sales-lines`).
- **Le contenu des documents est en français** ; seuls les noms de fichiers, de tables et de colonnes sont en anglais.
- **Pas d'abréviation obscure** : `quantity` plutôt que `qty`, `customer` plutôt que `cust`. Exceptions admises car universelles : `id`, `eur`, `pct`, `fx` (change).
- **Un nom décrit le contenu, jamais l'étape du projet** : les phases sont notre organisation de travail, le sujet d'un document reste valable après.

## 2. Les documents (`docs/`)

| Règle | Exemple |
| --- | --- |
| Préfixe à deux chiffres pour l'ordre de lecture, puis le sujet | `01_data_model_and_business_rules.md` |
| Sous-dossier par famille, numéroté de la même façon ; dans `docs/sources/`, un document par source, nommé comme la source (section 4) | `docs/sources/01_legacy_erp.md`, `docs/sources/02_m3.md` |
| Titre en français en première ligne, puis une ligne en italique indiquant la phase de rédaction | `# Modèle de données et règles métier` |
| Un sommaire, `docs/README.md`, liste les documents dans l'ordre avec une phrase sur chacun | — |

## 3. La configuration (`config/`)

- Un sous-dossier par contexte métier : `config/delta_plus/`. Adapter le projet à un autre secteur, c'est créer un autre sous-dossier.
- Fichiers YAML nommés par contenu : `master_data.yml`, `effect_types.yml`, `defect_types.yml`.
- Les clés YAML suivent les mêmes règles que les colonnes (section 5).

## 4. Les tables

**Les données brutes gardent leurs noms d'origine.** Dans la couche `raw`, on ne renomme rien : les noms cryptiques de l'ancien ERP et les noms de type M3 (`OOHEAD`, `OOLINE`) restent tels quels, pour pouvoir toujours remonter à la source. Le renommage se fait une seule fois, dans la couche de staging.

**Les modèles dbt suivent les conventions de dbt Labs :**

| Couche | Préfixe | Forme | Exemple |
| --- | --- | --- | --- |
| Staging : une table par table source, renommée et typée | `stg_` | `stg_<source>__<entités>` (deux tirets bas entre la source et l'entité) | `stg_legacy_erp__order_lines`, `stg_m3__customers` |
| Intermédiaire : assemblages et calculs | `int_` | `int_<entités>_<action>` | `int_sales_lines_unioned`, `int_sales_lines_converted` |
| Correspondances entre systèmes | `map_` | `map_<entités>` | `map_products`, `map_customers`, `map_transactions` |
| Faits : un événement, au pluriel | `fct_` | `fct_<événements>` | `fct_sales_lines`, `fct_deliveries` |
| Dimensions : un objet de référence, au singulier | `dim_` | `dim_<objet>` | `dim_product`, `dim_customer`, `dim_date` |

**Les noms des sources** sont toujours les mêmes, dans dbt, dans la colonne `source_system` et dans les noms de fichiers :

| Source | Nom |
| --- | --- |
| Ancien ERP | `legacy_erp` |
| Nouvel ERP (export de type Infor M3) | `m3` |
| CRM | `crm` |
| Fichier de la filiale brésilienne | `brazil_file` |
| Budget | `budget` |
| Taux de change de la BCE | `ecb_fx` |

## 5. Les colonnes

Le suffixe d'une colonne dit ce qu'elle contient.

| Contenu | Règle | Exemples |
| --- | --- | --- |
| Identifiant d'un objet de référence | `<objet>_id` | `product_id`, `customer_id`, `entity_id` |
| Clé technique créée par dbt dans les modèles finaux | `<objet>_key` | `product_key`, `customer_key` |
| Numéro d'un document métier | `<document>_number` | `order_number`, `invoice_number`, `delivery_number` |
| Numéro de ligne dans un document | `<document>_line_number` | `order_line_number`, `invoice_line_number` |
| Code lisible venant d'une source ou d'une norme | `<objet>_code` | `product_code` (`GNT-204`), `currency_code` (`EUR`) |
| Libellé | `<objet>_name` | `product_name`, `entity_name` |
| Date | `<événement>_date` | `order_date`, `promised_date`, `invoice_date`, `month_start_date` |
| Date et heure | `<événement>_at` | `loaded_at`, `matched_at` |
| Vrai ou faux | `is_<état>` ou `has_<chose>` | `is_intercompany`, `is_credit_note`, `has_migration_reference` |
| Montant | `<nature>_amount_<devise>` | `net_amount_eur`, `net_amount_local`, `list_price_amount_local` |
| Quantité | `<nature>_quantity` | `ordered_quantity`, `shipped_quantity`, `open_quantity` |
| Taux ou ratio, entre 0 et 1 | `<nature>_rate` | `discount_rate`, `fx_rate` |
| Nombre d'éléments | `<chose>_count` | `line_count` |
| Statut ou catégorie | `<objet>_status` ou `<objet>_type` | `match_status`, `document_type` |

Deux règles complémentaires :

- **Un montant en devise locale est toujours accompagné de sa devise** : `net_amount_local` va avec `currency_code`.
- **Toute ligne qui vient d'une source garde la trace de son origine** dans `source_system`, avec les noms de la section 4.

## 6. Git

- **Messages de commit** au format Conventional Commits, en anglais, en minuscules, à l'impératif : `type: description` (`docs: add naming conventions`, `feat: add sales staging models`).
- **Types utilisés** : `feat` (fonctionnalité ou modèle), `fix` (correction), `docs` (documentation), `chore` (outillage), `refactor` (réorganisation sans changement de résultat), `test` (tests).
- **Branches** : `<type>/<sujet-court>`, par exemple `feat/sales-staging` ou `fix/otif-first-promise`.
