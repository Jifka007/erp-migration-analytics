# Documentation du projet

Les documents se lisent dans l'ordre de leur numéro.

| Document | Ce qu'il contient |
| --- | --- |
| [00_naming_conventions.md](00_naming_conventions.md) | Les règles de nommage des documents, tables, colonnes et commits |
| [01_data_model_and_business_rules.md](01_data_model_and_business_rules.md) | Les tables de faits et leur grain (avec un exemple suivi de bout en bout), la définition de chaque indicateur, la justification des hypothèses pour Delta Plus, le rapprochement des transactions entre les deux ERP, le journal de réconciliation, la table des anomalies et la page qualité, le protocole à l'aveugle (période cachée, prévision, grille d'évaluation) et les idées pour plus tard |
| [02_reference_data.md](02_reference_data.md) | Le référentiel maître du groupe fictif : entités, devises, plateformes, gammes et familles, fournisseurs, segments clients et dates clés, avec la source de chaque choix. Les valeurs sont dans `config/delta_plus/master_data.yml` |
| [../config/delta_plus/](../config/delta_plus/) | Le référentiel (`master_data.yml`), les catalogues publics des effets (`effect_types.yml`) et des défauts (`defect_types.yml`), et l'empreinte du scénario scellé (`scenario_fingerprint.txt`) |
| [sources/01_legacy_erp.md](sources/01_legacy_erp.md) | L'ancien ERP : ses onze tables aux noms codés, chaque colonne et sa traduction, une vente suivie de bout en bout et la conséquence pour l'OTIF. Le schéma relationnel est dans `sources/01_legacy_erp.dbml` (à coller dans dbdiagram.io) |
| [sources/02_m3.md](sources/02_m3.md) | L'export de type Infor M3 : la hiérarchie société, division, entrepôt, les tables vérifiées et leurs champs, les versions des lignes de commande (première date promise), le stock reconstruit à partir des mouvements, la bascule vue depuis M3. Le schéma est dans `sources/02_m3.dbml` |
| [sources/03_crm.md](sources/03_crm.md) | Le CRM : des réponses d'API paginées en JSON imbriqué (comptes, contacts, visites, opportunités), l'extraction incrémentale et le rapprochement des comptes avec les clients des deux ERP (`map_crm_accounts`, appuyée sur `map_customers`). Un exemple valide est dans `sources/03_crm_example.json` |
| [sources/04_brazil_file.md](sources/04_brazil_file.md) | Le fichier Excel mensuel de la filiale brésilienne : en-têtes en portugais, montants en réals, produits du groupe et produits locaux (mesure de l'intégration), pièges d'un fichier saisi à la main |
| [sources/05_budget.md](sources/05_budget.md) | Le budget saisi par la finance dans Google Sheets : format large à dépivoter, périmètre comparable (le piège du Brésil), pièges d'une feuille saisie à la main |
