# Documentation du projet

Les documents se lisent dans l'ordre de leur numéro.

| Document | Ce qu'il contient |
| --- | --- |
| [00_naming_conventions.md](00_naming_conventions.md) | Les règles de nommage des documents, tables, colonnes et commits |
| [01_data_model_and_business_rules.md](01_data_model_and_business_rules.md) | Les cinq tables de faits et leur grain (avec un exemple suivi de bout en bout), la définition de chaque indicateur, la justification des hypothèses pour Delta Plus, le rapprochement des transactions entre les deux ERP, le journal de réconciliation, le protocole à l'aveugle et les idées pour plus tard |
| [02_reference_data.md](02_reference_data.md) | Le référentiel maître du groupe fictif : entités, devises, plateformes, gammes et familles, fournisseurs, segments clients et dates clés, avec la source de chaque choix. Les valeurs sont dans `config/delta_plus/master_data.yml` |
| [sources/01_legacy_erp.md](sources/01_legacy_erp.md) | L'ancien ERP : ses onze tables aux noms codés, chaque colonne et sa traduction, une vente suivie de bout en bout et la conséquence pour l'OTIF. Le schéma relationnel est dans `sources/01_legacy_erp.dbml` (à coller dans dbdiagram.io) |
| [sources/02_m3.md](sources/02_m3.md) | L'export de type Infor M3 : la hiérarchie société, division, entrepôt, les tables vérifiées et leurs champs, les versions des lignes de commande (première date promise), le stock reconstruit à partir des mouvements, la bascule vue depuis M3. Le schéma est dans `sources/02_m3.dbml` |

À venir, au fil de la conception : la description des autres sources dans `sources/` (CRM, fichiers bureautiques).
