# Documentation du projet

Les documents se lisent dans l'ordre de leur numéro.

| Document | Ce qu'il contient |
| --- | --- |
| [00_naming_conventions.md](00_naming_conventions.md) | Les règles de nommage des documents, tables, colonnes et commits |
| [01_data_model_and_business_rules.md](01_data_model_and_business_rules.md) | Les cinq tables de faits et leur grain (avec un exemple suivi de bout en bout), la définition de chaque indicateur, la justification des hypothèses pour Delta Plus, le rapprochement des transactions entre les deux ERP, le journal de réconciliation, le protocole à l'aveugle et les idées pour plus tard |
| [02_reference_data.md](02_reference_data.md) | Le référentiel maître du groupe fictif : entités, devises, plateformes, gammes et familles, fournisseurs, segments clients et dates clés, avec la source de chaque choix. Les valeurs sont dans `config/delta_plus/master_data.yml` |
| [sources/01_legacy_erp.md](sources/01_legacy_erp.md) | L'ancien ERP : ses onze tables aux noms codés, chaque colonne et sa traduction, une vente suivie de bout en bout et la conséquence pour l'OTIF. Le schéma relationnel est dans `sources/01_legacy_erp.dbml` (à coller dans dbdiagram.io) |
| [sources/02_m3.md](sources/02_m3.md) | L'export de type Infor M3 : la hiérarchie société, division, entrepôt, les tables vérifiées et leurs champs, les versions des lignes de commande (première date promise), le stock reconstruit à partir des mouvements, la bascule vue depuis M3. Le schéma est dans `sources/02_m3.dbml` |
| [sources/03_crm.md](sources/03_crm.md) | Le CRM : des réponses d'API paginées en JSON imbriqué (comptes, contacts, visites, opportunités), l'extraction incrémentale et le rapprochement des comptes avec les clients des deux ERP (`map_crm_accounts`, appuyée sur `map_customers`). Un exemple valide est dans `sources/03_crm_example.json` |

À venir, au fil de la conception : le fichier de la filiale brésilienne (`04_brazil_file.md`) et le budget (`05_budget.md`).
