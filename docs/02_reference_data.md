# Référentiel maître du groupe fictif

*Rédigé en phase 1 (conception des sources), tâche 1.1, octobre 2026. Les valeurs sont dans [`config/delta_plus/master_data.yml`](../config/delta_plus/master_data.yml) ; ce document explique et source chaque choix.*

Le référentiel maître contient les **données de référence** du groupe : les filiales, les plateformes, les gammes et familles d'articles, les fournisseurs et les segments clients. Ce sont les « noms propres » que toutes les transactions utilisent : une ligne de commande, c'est un client qui commande un article à une filiale. Ce référentiel est la vérité commune ; chaque source (ancien ERP, M3, fichier brésilien, CRM) en tire ensuite sa propre version, avec ses propres codes. C'est exactement ce qui casse dans une migration ERP : un même article ou un même client sous deux codes différents.

Les sources suivent la légende du document [01](01_data_model_and_business_rules.md) : **Delta Plus** (publié par le groupe), **Pratique courante**, **Hypothèse**. Le groupe est fictif : la structure et les proportions sont calibrées sur Delta Plus, les montants sont synthétiques.

## 1. Ce qu'on sait de Delta Plus

- **Le métier** : le groupe conçoit, fabrique et distribue des équipements de protection individuelle, « de la tête aux pieds », et de la protection collective depuis 2017. Environ 8 000 références, 18 sites de production, plus de 40 filiales. *(Delta Plus)*
- **Faire ou acheter** : tout est conçu en interne et vendu sous la marque du groupe, mais seule une partie est fabriquée en interne (environ 45 % du CA en 2021 ; le site du groupe affiche aujourd'hui 85 % de produits fabriqués dans 20 usines, une hausse cohérente avec les usines rachetées depuis, mais non détaillée par gamme). L'antichute est fabriquée à 100 % en interne, la tête à 70-90 %, les chaussures à environ 50-75 % selon les sources ; les gants et les vêtements sont entièrement sous-traités. La logique : garder ce qui est critique pour la sécurité, sous-traiter ce qui demande beaucoup de main-d'œuvre. *(Delta Plus, interviews du dirigeant 2022 et 2023)*
- **Les canaux** : le groupe vend à des distributeurs, jamais directement aux utilisateurs. Les distributeurs servent les grands comptes (BTP, industrie, aéronautique). *(Delta Plus)*

## 2. Les entités

| `entity_id` | Pays | Zone | Devise | `is_platform` | `has_external_sales` | Source avant / après le 7 avril 2026 | Dans le périmètre depuis |
| --- | --- | --- | --- | --- | --- | --- | --- |
| FR | France | Europe | EUR | oui | oui | `legacy_erp` / `m3` | début de l'historique |
| DE | Allemagne | Europe | EUR | non | oui | `legacy_erp` / `m3` | début de l'historique |
| ES | Espagne | Europe | EUR | non | oui | `legacy_erp` / `legacy_erp` | début de l'historique |
| CN | Chine | Hors Europe | CNY | oui | oui | `legacy_erp` / `legacy_erp` | début de l'historique |
| AE | Émirats arabes unis | Hors Europe | AED | non | oui | `legacy_erp` / `legacy_erp` | début de l'historique |
| BR | Brésil | Hors Europe | BRL | non | oui | `brazil_file` | 1er janvier 2026 |

**Une entité est une société, un site est un lieu.** Une entité est une société juridique : elle a ses comptes, sa devise, ses factures, et c'est la « société » de l'ERP (`CONO` dans M3) ; elle se lit sur l'axe `dim_entity`. Un site est un lieu physique (un entrepôt, une usine) qui appartient à une entité ; les plateformes se lisent sur l'axe `dim_warehouse`. La France est une entité (`FR`), Apt est son site (`FR-APT`).

**Les types d'entités.** Ce ne sont pas des cases exclusives : ils se cumulent, d'où les deux booléens plutôt qu'un rôle unique.

| Type | Définition | Ce que ça recouvre dans les données | Dans le groupe fictif |
| --- | --- | --- | --- |
| Filiale | Toute société détenue par le groupe ; terme général qui couvre les types suivants | Une ligne de `dim_entity`, avec sa devise et son système source | Les 6 entités |
| Filiale commerciale (ou de distribution) | Achète au groupe et revend à des clients de son pays ; ne fabrique pas et n'approvisionne personne | Ventes extérieures, commandes, budget ; ses achats internes ne sont vus que côté vendeur ; stock non suivi | Allemagne, Espagne, Émirats, Brésil |
| Plateforme (logistique) | Entrepôt central qui reçoit des usines et des fournisseurs, stocke et redistribue aux filiales | Ventes internes, stock mensuel, sorties, couverture, dépréciation | Apt (France) et Shanghai (Chine) |
| Entité mixte | Porte une plateforme et vend aussi à ses propres clients | Les deux activités, chacune jugée avec ses indicateurs (document 01, section 2) | France, Chine |
| Plateforme pure | Ne vend qu'aux autres entités | CA consolidé nul, vue logistique seulement | Aucune (cas théorique) |
| Base amont (usine) | Fabrique ou achète en Asie et expédie vers les plateformes, sans vendre aux clients | Un fournisseur interne (`is_internal: true`) : on sait seulement quelles familles en viennent | Inde, et l'usine chinoise |
| Entité acquise | Filiale entrée dans le périmètre en cours de période | Sa date d'entrée (`consolidation_start_date`) alimente l'effet de périmètre et la croissance organique | Brésil (1er janvier 2026) |
| Siège (société mère) | Détient les filiales et publie les comptes consolidés | Pas une entité dans les données : c'est le point de vue du groupe, la somme des contributions | Delta Plus Group, à Apt |

Les mots varient d'une entreprise à l'autre (« hub », « centre de distribution » pour une plateforme) ; Delta Plus parle de « plateformes » et de « bases amont ». Enfin, une entité porte aussi son système source : l'Espagne et l'Allemagne sont deux filiales commerciales, mais l'une est restée sur l'ancien ERP et l'autre est passée sur M3. Pour la migration, cet attribut compte autant que le type.

**Le pays en clair.** Chaque entité porte son code pays (`country_code`, norme ISO) et son nom en français (`country_name`), pour que les rapports restent lisibles sans table de correspondance. La ville n'est donnée que pour les plateformes (Apt, Shanghai), seules villes appuyées par une source ; pour les filiales commerciales, le pays suffit.

**Deux booléens plutôt qu'un rôle.** Une entité peut approvisionner d'autres filiales (`is_platform`) et vendre à des clients extérieurs (`has_external_sales`) : ce ne sont pas deux catégories exclusives. Apt est à la fois siège, plateforme logistique et entité qui vend en France *(Delta Plus)*. Les ventes locales de la Chine sont une *hypothèse*. Un rôle unique (« plateforme » ou « commerciale ») aurait été faux pour la France ; Delta Plus ne publie d'ailleurs pas une telle distinction.

**Ce que ça change pour le pilotage.** Le CA interne d'une plateforme disparaît en consolidation : elle se juge sur ses expéditions aux filiales et son stock. Son CA extérieur se juge comme celui de n'importe quelle filiale.

**Le poids des entités** (`revenue_share`) : environ 50 % en Europe et 50 % hors Europe *(Delta Plus)* ; le Brésil pèse environ 10 % du groupe, pour reproduire l'effet de périmètre de +10 % publié au S1 2026 *(Delta Plus)*. La répartition fine entre filiales est une *hypothèse*.

**La plateforme qui approvisionne chaque filiale** (`supplying_warehouse_id`) : l'Europe par Apt, les Émirats par la Chine *(hypothèse)*. La filiale des Émirats est installée en zone franche à Sharjah *(Delta Plus)*, un emplacement typique d'un stock de réexportation vers le Golfe ; d'où vient sa marchandise n'est pas public. La Chine est retenue parce qu'elle concentre la production du groupe et qu'elle est plus proche que la France. Le Brésil garde ses propres outils, son stock n'est pas suivi.

## 3. Les devises

| Devise | Taux EUR → devise | Pourquoi |
| --- | --- | --- |
| EUR | aucun | Devise du groupe |
| CNY, BRL, USD | Taux de référence de la BCE | Publiés directement par la BCE |
| AED | Taux EUR → USD de la BCE × 3,6725 | La BCE ne publie pas l'AED ; le dirham est arrimé au dollar à 3,6725 depuis 1997, donc ce taux croisé est exact |

Conséquence à savoir expliquer : l'effet de change des Émirats est en réalité un effet dollar. Les taux sont les taux réels de la BCE : l'effet de change de 2025 apparaît de lui-même.

## 4. Les plateformes

| `warehouse_id` | Plateforme | Entité |
| --- | --- | --- |
| FR-APT | Apt | FR |
| CN-SHA | Shanghai | CN |

Ce sont les seuls stocks suivis (voir le document 01). Delta Plus a une plateforme à Apt et un entrepôt en Chine près de Shanghai *(Delta Plus)* ; le groupe réel a d'autres plateformes en Europe, que le projet ne reproduit pas.

## 5. Les gammes et les familles

**Trois gammes, qui ont trois modes d'approvisionnement différents** : les chaussures (mixtes), l'antichute (100 % interne) et les gants (100 % sous-traités). La tête et les vêtements ne sont pas repris : ils ne répondent à aucune des cinq questions de plus que ces trois gammes.

| Gamme | Famille | `sourcing_type` | Prix distributeur | Saisonnalité | Ce qui la distingue |
| --- | --- | --- | --- | --- | --- |
| Chaussures (50 %) | Basses | sous-traitée *(hypothèse)* | 25 à 45 € | non | Gros volumes, prix bas |
| | Montantes | interne | 35 à 70 € | non | Cœur de gamme BTP |
| | Bottes | interne | 20 à 50 € | hiver | Saisonnières |
| Antichute (32 %) | Harnais et longes | interne | 15 à 120 € | non | Rotation régulière |
| | Antichutes à rappel automatique | interne | 150 à 600 € | non | Prix élevé, rotation lente |
| Gants (18 %) | Manutention | sous-traitée | 1 à 4 € | non | Très gros volumes, prix très bas |
| | Anti-coupure | sous-traitée | 3 à 10 € | non | Montée en gamme |
| | Thermiques | sous-traitée | 4 à 12 € | hiver | Saisonniers |

**Les sources.** Les noms de familles viennent du catalogue en ligne de Delta Plus, regroupés quand deux catégories ont les mêmes caractéristiques *(Delta Plus)*. Le poids des gammes reprend les proportions publiées entre pieds, antichute et mains, ramenées à 100 % *(Delta Plus, calibrage du cadrage)*. Le mode d'approvisionnement par gamme est publié ; par famille, pour les chaussures, c'est une *hypothèse* : les basses, les plus standardisées, sont sous-traitées. Les prix et les poids des familles sont des *hypothèses* d'ordre de grandeur.

**Comment la liste a été critiquée.** Cinq tests : la famille existe chez Delta Plus ; elle se distingue de ses voisines sur un paramètre qui fait bouger un indicateur (prix, rotation, saisonnalité, mode d'approvisionnement) ; chaque article est dans une seule famille ; elle pèse assez pour être analysée ; elle vaut son coût. Résultat : les harnais et les longes sont fusionnés (mêmes paramètres, souvent vendus ensemble) ; les gants chimiques sont écartés (aucun paramètre distinct des gants anti-coupure), les gants thermiques gardés pour leur saisonnalité.

**Le coût groupe.** Chaque famille a un ratio coût groupe / prix (`cost_ratio`) : environ 0,36 à 0,40 pour ce qui est fabriqué en interne, 0,50 pour ce qui est sous-traité *(hypothèse : le sous-traitant prend sa marge)*. Pondéré par le poids des gammes, on obtient une marge brute d'environ 57 %, dans la zone publiée par Delta Plus (56 à 58 %). C'est ce coût groupe, porté par la fiche article, que le projet utilise pour la marge et la valeur du stock (document 01).

**Le grain de l'article.** Un article est un modèle, sans taille. Dans la réalité, un modèle de chaussure a une référence par pointure ; c'est une extension (voir le document 01, section 8). Les quantités sont en unité de base : la paire pour les chaussures et les gants, la pièce pour l'antichute.

**Analyser par famille, montrer par article.** Les analyses se font au niveau de la famille. Dans Power BI, la hiérarchie gamme → famille → article de `dim_product` permet de descendre jusqu'à l'article (*drill down*) pour illustrer un cas, sans coût d'analyse supplémentaire.

## 6. Les fournisseurs

| `supplier_id` | Fournisseur | Pays | Interne | Familles |
| --- | --- | --- | --- | --- |
| SUP-CN-01 | Usine du groupe, Chine | CN | oui | Montantes, bottes, antichute |
| SUP-IN-01 | Usine du groupe, Inde | IN | oui | Montantes, bottes |
| SUP-EXT-01 | Sous-traitant chaussures A | VN | non | Basses |
| SUP-EXT-02 | Sous-traitant gants A | PK | non | Manutention |
| SUP-EXT-03 | Sous-traitant gants B | LK | non | Anti-coupure, thermiques |

**L'Inde est une usine, pas une entité.** Une plateforme est un entrepôt qui reçoit, stocke et redistribue ; l'Inde fabrique et expédie vers les plateformes. Les usines de Chine et d'Inde fabriquent des chaussures et des pièces injectées *(Delta Plus)*. Dans la réalité, la filiale indienne vend aussi probablement en Inde : le projet la simplifie en fournisseur interne, sans ventes ni stock suivi, car une entité de plus ajouterait des flux sans répondre à aucune des cinq questions.

Les noms des sous-traitants sont fictifs : Delta Plus ne les publie pas. Leurs pays sont appuyés : les données douanières partielles de la filiale des Émirats montrent des gants importés du Pakistan (gants en cuir) et du Sri Lanka (gants tricotés) *(Delta Plus, données douanières Trademo, échantillon partiel)* ; le Vietnam est le deuxième exportateur mondial de chaussures *(pratique courante du secteur)*. Dans le cœur, les fournisseurs servent seulement à dire d'où vient chaque famille ; les commandes et réceptions fournisseurs sont une extension.

## 7. Les clients

| `customer_segment_id` | Segment | Poids dans le CA extérieur |
| --- | --- | --- |
| BUILDERS_MERCHANT | Négoce BTP et agricole | 55 % |
| PPE_SPECIALIST | Distributeur spécialiste EPI | 27 % |
| GENERALIST | Distributeur généraliste | 9 % |
| DIY_RETAIL | Grande surface de bricolage | 9 % |
| INTERCOMPANY | Entité du groupe | hors CA consolidé |

**Les segments sont les canaux publiés par Delta Plus** *(Delta Plus, interview du dirigeant, 2023)*. Les ordres de grandeur cités dépassent 100 % au total ; ils sont ramenés à 100 % en gardant leur ordre *(hypothèse)*. Le poids du négoce BTP est cohérent avec l'actualité : au S1 2026, le recul européen vient de la contraction du BTP français *(Delta Plus)*.

**Les clients internes.** Chaque entité approvisionnée par une plateforme est aussi cliente de cette plateforme, avec le segment `INTERCOMPANY` et l'entité qu'elle représente. C'est de là que vient `is_intercompany` sur les lignes de commande et de vente.

Le nombre de clients extérieurs par entité (`customer_counts_full_scale`, donné pour le groupe complet, voir la section 9) est une *hypothèse*. Les clients eux-mêmes, avec leurs noms et leurs codes dans chaque système, seront produits par le générateur.

## 8. Les dates clés

| Date | Événement | Source |
| --- | --- | --- |
| 1er janvier 2024 | Début de l'historique | Hypothèse |
| 1er janvier 2026 | Entrée du Brésil dans le périmètre | Hypothèse, calée sur les acquisitions de Delta Plus en Amérique latine |
| 26 mars 2026 | Début de l'interruption avant la bascule | Delta Plus |
| 7 avril 2026 | Bascule de la France et de l'Allemagne vers M3 | Delta Plus |
| 30 septembre 2026 | Fin de l'historique | Hypothèse |

## 9. L'échelle et les ratios de vraisemblance

**L'échelle est un paramètre** (`scale_factor`). Le groupe complet (`scale_factor` = 1) reproduit l'ordre de grandeur de Delta Plus : environ 390 M€ de CA, 680 modèles, 5 100 clients extérieurs. Le générateur tire un **échantillon de clients** : au 1/10e, il garde 10 % des clients, donc environ 10 % du CA (environ 39 M€ par an, environ 130 000 lignes de commande sur 33 mois). Le catalogue, lui, ne change pas.

**Pourquoi le 1/10e par défaut.** Le bruit relatif d'une moyenne baisse comme 1/√n. Au 1/10e, une case d'analyse (famille × filiale × mois) compte environ 80 lignes, assez pour qu'un phénomène sorte du bruit ; au 1/1, environ 800 lignes, pour un gain faible. En revanche, chaque régénération et chaque chargement par Airbyte, sur un ordinateur portable, deviendrait dix fois plus long. Enfin, une échelle visiblement réduite évite toute confusion avec les vrais chiffres de Delta Plus, même si les données sont présentées comme synthétiques. Le 1/1 sert de **test de charge**, une fois la chaîne terminée.

**Une règle pour la tâche 1.6** : les histoires cachées sont exprimées en pourcentages, jamais en euros, pour que les conclusions soient les mêmes à toutes les échelles.

**Les ratios de vraisemblance**, à vérifier par un test après la génération (phase 2) :

| Ratio | Cible | Source |
| --- | --- | --- |
| CA moyen par client extérieur et par an | Environ 76 k€ (390 M€ / 5 100), indépendant de l'échelle | Hypothèse : des distributeurs, du négoce local au grand réseau |
| CA par modèle, au 1/1 | Environ 570 k€ (390 M€ / 680) | Delta Plus : environ 49 k€ par référence (390 M€ / 8 000), soit environ 500 k€ par modèle décliné en une dizaine de tailles |
| Marge brute | 56 à 58 % | Delta Plus |
| Poids des gammes | Environ 50 / 32 / 18 % | Delta Plus, ramené à trois gammes |
| Part de l'Europe | Environ 50 % | Delta Plus |
| Couverture du stock | De l'ordre de 8 mois | Delta Plus (document 01, section 3) |
| Valeur moyenne d'une ligne, lignes par commande | À fixer en 1.6 | Hypothèse |

## Sources

- [TPBM, « Delta Plus Group, leader indépendant des équipements de protection à l'international » (février 2023)](https://mesinfos.fr/provence-alpes-cote-d-azur/delta-plus-group-leader-independant-des-equipements-de-protection-a-l-international-120836.html)
- [Zonebourse, « Delta Plus Group : équipés de la tête aux pieds » (mai 2022)](https://www.zonebourse.com/cours/action/DELTA-PLUS-GROUP-37879274/actualite/Delta-Plus-Group-equipes-de-la-tete-aux-pieds-40299366/)
- [Le Moci, « Delta Plus rentabilise son dispositif chinois »](https://lemoci.com/actualites/actualites/logistique-delta-plus-rentabilise-son-dispositif-chinois)
- [Delta Plus, résultats semestriels 2026](https://media.deltaplus.eu/asset/bc1d5cfc-3229-410f-989e-2871f7a15dc1/31-08-26-Communique-Delta-Plus-Group-Resultats-semestriels-2026.pdf)
- [Delta Plus, catalogue en ligne](https://www.deltaplus.eu/en-US/)
- [Delta Plus, présentation du groupe](https://www.deltaplus.eu/en/our-company)
- [Trademo, importations de Delta Plus Middle East](https://www.trademo.com/companies/delta-plus-middle-east/17880626)
- [Oil & Gas Directory, Delta Plus Middle East FZE (Saif Zone, Sharjah)](https://www.oilandgasdirectory.com/profile/details/18852/Delta-Plus-Middle-East-FZE.html)
- [Gouvernement vietnamien, le Vietnam deuxième exportateur mondial de chaussures](https://en.baochinhphu.vn/viet-nam-sustains-worlds-second-largest-footwear-exporter-111240401201158442.htm)
- [The National, l'arrimage du dirham au dollar](https://www.thenationalnews.com/lifestyle/2024/11/22/uae-dirham-dollar-peg)
- [BCE, table des taux de référence (exemple)](https://www.ecb.europa.eu/stats/exchange/eurofxref/shared/pdf/2020/02/20200203.pdf)
