# Modèle de données et règles métier

*Les décisions structurantes du projet, fixées avant d'écrire le code. Rédigé en phase 1 (conception des sources), octobre 2026.*

Ce document fixe les règles dont dépend tout le projet : le grain de chaque table de faits, la définition de chaque indicateur, le rapprochement des transactions entre les deux ERP, le journal de réconciliation et le protocole à l'aveugle. Il est écrit avant toute ligne de code : le générateur (phase 2), l'ingestion (phase 3) et dbt (phase 4) ne font qu'appliquer ces règles.

**Comment lire les règles.** Chaque règle indique d'où elle vient :

- **Norme** : imposée par une norme comptable (IFRS) ;
- **Delta Plus** : méthode publiée par Delta Plus dans sa communication financière ;
- **Pratique courante** : ce que font la plupart des entreprises ;
- **Hypothèse** : un choix raisonnable faute de règle connue.

Les données sont fictives : toutes ces règles seraient à valider avec les équipes concernées dans une vraie entreprise. La colonne « À valider avec » dit avec qui.

**Cœur ou extension.** Toutes les règles sont documentées, mais seules celles du **cœur** sont construites en priorité : ce sont celles qui servent directement les cinq questions du projet. Les règles marquées **(extension)** ne sont construites que s'il reste du temps. Les nouvelles idées ne s'ajoutent plus à ce document : elles vont dans la liste de la section 8.

## 1. Les tables de faits et leur grain

Une commande, une expédition et une facture sont trois événements différents. Une commande de 100 paires peut être expédiée en deux fois (60 puis 40), donner lieu à deux factures, puis à un avoir. Chaque table de faits porte donc un seul grain : une ligne de la table correspond à un seul type d'événement.

**Comment lire le tableau ci-dessous :**

- **Une ligne =** : le grain, c'est-à-dire ce que représente une ligne de la table, et rien d'autre.
- **Clé** : les colonnes qui, ensemble, identifient une ligne de façon unique ; deux lignes ne peuvent jamais avoir la même clé, et un test dbt le vérifie.
- **Dates principales** : les dates présentes sur chaque ligne, qui la placent dans le temps.
- **Mesures** : les nombres qu'on additionne ou qu'on calcule (quantités, montants).

| Table | Une ligne = | Clé | Dates principales | Mesures |
| --- | --- | --- | --- | --- |
| `fct_order_lines` | une ligne de commande | `entity_id`, `order_number`, `order_line_number`, `order_line_suffix`, `source_system` | commande, demandée, première date promise, date promise actuelle, annulation | quantité commandée, quantité restant à livrer, quantité annulée, montant ; indicateur de vente entre filiales ; pour l'OTIF : date de la dernière expédition et quantité totale expédiée, reprises des expéditions |
| `fct_deliveries` | une expédition d'une ligne de commande | `delivery_number`, clé de la ligne de commande | expédition, première date promise | quantité expédiée, plateforme d'expédition (`warehouse_id`) |
| `fct_sales_lines` | une ligne de facture ou d'avoir | `entity_id`, `invoice_number`, `invoice_line_number`, `source_system` | facture | quantité, montant en devise locale, en euros, aux taux de l'année précédente, coût de revient ; indicateur de vente entre filiales ; liens vers la ligne de commande et l'expédition facturées ; pour un avoir : son type et la facture d'origine |
| `fct_stock_snapshots` | un article, une plateforme, une fin de mois | `product_id`, `warehouse_id`, `month_end_date` | fin de mois, dernière sortie | quantité en stock, coût moyen pondéré, valeur brute, dépréciation, valeur nette ; sorties des trois derniers mois, mois par mois |
| `fct_budget` | une filiale, une gamme, un mois | `entity_id`, `product_line_id`, `month_start_date` | mois | chiffre d'affaires cible |

**Une histoire pour comprendre les cinq tables.** La filiale française (société `FR`) reçoit le 3 mars, dans l'ancien ERP, la commande 45872 d'un distributeur : 100 paires de gants (ligne 1) et 20 casques (ligne 2). On suit les gants. Les noms de colonnes sont indicatifs : ils seront fixés précisément lors de la conception des sources.

*1. `fct_order_lines` : une ligne par ligne de commande.*

| entity_id | order_number | order_line_number | order_line_suffix | source_system | order_date | requested_date | first_promised_date | ordered_quantity | open_quantity | net_amount_eur |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FR | 45872 | 1 | 0 | legacy_erp | 3 mars | 20 mars | 18 mars | 100 | 0 | 1 000 |
| FR | 45872 | 2 | 0 | legacy_erp | 3 mars | 20 mars | 18 mars | 20 | 0 | 400 |

La clé a cinq colonnes, et chacune évite un doublon : `order_line_number` parce qu'une commande a plusieurs lignes ; `entity_id` (la filiale, qui correspond à la « société » des ERP, `CONO` dans M3) parce que la filiale allemande peut aussi avoir une commande n° 45872 ; `source_system` parce que l'ancien ERP et M3 peuvent réutiliser les mêmes numéros ; `order_line_suffix` parce que M3 peut découper une ligne en sous-lignes (0 quand il n'y en a pas).

*2. `fct_deliveries` : une ligne par expédition d'une ligne de commande.* Les gants partent en deux fois.

| delivery_number | entity_id | order_number | order_line_number | warehouse_id | shipped_date | first_promised_date | shipped_quantity |
| --- | --- | --- | --- | --- | --- | --- | --- |
| L-901 | FR | 45872 | 1 | FR-APT | 18 mars | 18 mars | 60 |
| L-934 | FR | 45872 | 1 | FR-APT | 28 mars | 18 mars | 40 |

La clé reprend celle de la ligne de commande : c'est elle qui relie l'expédition à sa commande. Cette ligne n'est pas OTIF : complète le 28 mars seulement, après la date promise du 18 mars.

*3. `fct_sales_lines` : une ligne par ligne de facture ou d'avoir.* Une facture par expédition, puis un avoir pour 5 paires abîmées.

| entity_id | invoice_number | invoice_line_number | source_system | delivery_number | invoice_date | quantity | net_amount_eur | cost_amount_eur | credit_note_type |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FR | F-5001 | 1 | legacy_erp | L-901 | 18 mars | 60 | 600 | 252 | — |
| FR | F-5043 | 1 | legacy_erp | L-934 | 28 mars | 40 | 400 | 168 | — |
| FR | A-0077 | 1 | legacy_erp | — | 10 avril | − 5 | − 50 | − 21 | retour |

CA de mars : 1 000 € ; marge brute de mars : 1 000 − 420 = 580 € ; CA d'avril : − 50 €, l'avoir étant compté à sa date d'émission.

*4. `fct_stock_snapshots` : une ligne par article, plateforme et fin de mois.* C'est une photo : le stock ne « sait » pas pour quelle commande il est, d'où une clé sans numéro de commande.

| product_id | warehouse_id | month_end_date | last_shipped_date | stock_quantity | unit_cost_amount_eur | gross_stock_amount_eur | impairment_amount_eur | net_stock_amount_eur |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| GNT-204 | FR-APT | 31 mars | 28 mars | 900 | 4,20 | 3 780 | 0 | 3 780 |
| GNT-204 | FR-APT | 30 avril | 22 avril | 850 | 4,20 | 3 570 | 0 | 3 570 |

On n'additionne jamais les mois entre eux : 900 + 850 ne veut rien dire.

*5. `fct_budget` : une ligne par filiale, gamme et mois.*

| entity_id | product_line_id | month_start_date | target_revenue_amount_eur |
| --- | --- | --- | --- |
| FR | HAND | 1er mars | 350 000 |

Le budget ne connaît ni commandes ni articles, seulement la gamme « mains » : on le compare au CA de mars de la France sur toute la gamme.

**Ce que montre l'histoire :** un même événement métier, la commande de 100 paires, laisse une trace différente dans chaque table : une ligne de commande, deux expéditions, deux factures et un avoir, une photo de stock par mois. Tout mettre dans une seule table ferait compter les 100 paires plusieurs fois. Les colonnes `product_id`, `entity_id` ou `warehouse_id` renvoient aux tables de dimensions (`dim_product`, `dim_entity`, `dim_warehouse`), où se trouvent le nom de l'article, sa gamme ou le pays de la filiale.

**Chaque table de faits porte aussi ses références** vers les dimensions : la filiale (`entity_id`, qui renvoie à `dim_entity`), le client, l'article, la plateforme. Les lignes de facture gardent en plus le lien vers la ligne de commande et l'expédition facturées : c'est ce lien qui permet d'appliquer le rapprochement des commandes migrées (section 4) au chiffre d'affaires, et de savoir de quelle plateforme part la marchandise vendue.

**La première date promise est conservée à part.** Quand une promesse est repoussée, un ERP écrase souvent l'ancienne date. Les lignes de commande gardent donc deux colonnes : `first_promised_date`, la promesse d'origine, utilisée par l'OTIF et l'écart de promesse, et `promised_date`, la promesse actuelle.

**Le budget a sa propre table**, car il est saisi par filiale, gamme et mois, alors que le chiffre d'affaires est à la ligne de facture. Les deux se comparent au niveau commun (filiale, gamme, mois), grâce aux dimensions partagées `dim_entity`, `dim_product` et `dim_date` (dimensions conformes, au sens de Kimball).

**Le fichier de la filiale brésilienne** contient des lignes de facture, comme un export comptable : il alimente directement `fct_sales_lines`, sans casser le grain. Il ne contient ni commandes, ni expéditions, ni stock : tant qu'elle n'est pas intégrée, la filiale brésilienne compte dans le CA, la marge et la croissance, mais pas dans l'OTIF, le carnet ni le stock. C'est une limite assumée, et un argument pour son intégration.

**Les règlements clients** (dates d'échéance et de paiement) ne font pas partie des sources du cœur du projet. Le délai de paiement (DSO) est une extension possible.

## 2. Les indicateurs

Chaque indicateur est rattaché à une seule table de faits. C'est le critère de fin de cette décision.

| Indicateur | Table | Règle | Source | À valider avec |
| --- | --- | --- | --- | --- |
| Chiffre d'affaires | `fct_sales_lines` | Lignes de facture moins lignes d'avoir, hors ventes entre filiales, à la date de facture, converties au taux moyen BCE du mois de la facture. Jamais calculé sur les commandes ni les expéditions | Norme (IFRS 15 pour le moment, IFRS 10 pour les ventes entre filiales), Delta Plus (risques transférés à l'expédition dans leurs conditions générales de vente), pratique courante (taux moyen) et hypothèse (facture émise à l'expédition) | Direction financière |
| Croissance organique | `fct_sales_lines` | CA de l'année recalculé aux taux de change de l'année précédente ; contribution des entités acquises dans l'année retirée ; pour une entité acquise l'année précédente, contribution retirée du 1er janvier jusqu'à la fin du mois anniversaire de l'acquisition ; règle symétrique pour les cessions | Delta Plus | Direction financière |
| Effet de change | `fct_sales_lines` | CA publié moins CA recalculé aux taux de l'année précédente (taux moyen du même mois de l'année précédente) | Delta Plus | Direction financière |
| Effet de périmètre | `fct_sales_lines` | Contribution des entités acquises ou cédées sur la période, selon leur date d'entrée dans `dim_entity` | Delta Plus | Direction financière |
| Marge brute | `fct_sales_lines` | CA moins coût d'achat des marchandises vendues : coût d'origine pour le groupe (achat ou fabrication auprès de l'extérieur), jamais le prix de vente interne, en vigueur à la date de la vente et multiplié par la quantité. Le transport vers le client n'est pas dans ce coût. Montant et taux de marge dans le cœur ; décomposition de son évolution en effets prix, volume et mix (extension) | Delta Plus | Contrôle de gestion |
| Ventes internes | `fct_sales_lines` | Ventes dont le client est une entité du groupe (`is_intercompany` vrai), par entité qui vend et entité qui achète, comparées aux ventes externes de chaque entité. Le stock n'étant suivi que dans les plateformes, l'accumulation de stock chez une filiale n'est pas mesurée (voir section 8) | Pratique courante | Direction financière, supply chain |
| Écart au budget | `fct_budget` | CA réalisé moins CA cible, comparés par filiale, gamme et mois | Pratique courante | Contrôle de gestion |
| Prises de commandes | `fct_order_lines` | Montant des commandes enregistrées sur la période, à la date de commande, hors ventes entre filiales | Pratique courante | Direction commerciale |
| Carnet de commandes | `fct_order_lines` | Montant des quantités restant à livrer sur les commandes ouvertes, à une date donnée : quantité commandée, moins les quantités expédiées et annulées avant cette date, au prix de la ligne de commande | Pratique courante | Direction commerciale |
| Client actif | `fct_order_lines` | Client extérieur au groupe ayant passé au moins une commande sur les 12 derniers mois | Hypothèse | Direction commerciale |
| OTIF (*On Time In Full*) | `fct_order_lines` | Part des lignes de commande livrées à l'heure et en totalité : nombre de lignes OTIF divisé par le nombre de lignes dont la première date promise tombe dans la période. Une ligne est OTIF si sa dernière expédition (`shipped_date`) a lieu au plus tard à sa première date promise (`first_promised_date`) et si la quantité totale expédiée (`shipped_quantity`) égale la quantité commandée (`ordered_quantity`). Une expédition en avance compte comme à l'heure. La variante à la date demandée par le client (`requested_date`) est calculée aussi | Hypothèse (il n'existe pas de définition standard), appuyée par les conditions générales de vente de Delta Plus (expédition par transporteur, délais indicatifs) | Supply chain |
| Écart de promesse | `fct_order_lines` | Nombre de jours entre la date demandée par le client (`requested_date`) et la première date promise (`first_promised_date`), et part des lignes promises plus tard que demandé | Pratique courante | Supply chain, direction commerciale |
| Couverture de stock | `fct_stock_snapshots` | Pour un article : stock en quantité divisé par la quantité moyenne sortie par mois sur les trois derniers mois. Les sorties d'une plateforme comprennent les expéditions aux clients et les envois aux autres entités du groupe. Dès qu'on regroupe des articles (famille, plateforme, groupe) : stock en valeur au coût divisé par le coût moyen des marchandises sorties par mois. Exprimée en mois, toujours affichée avec l'évolution des ventes sur les trois mois | Pratique courante | Supply chain |
| Dépréciation du stock | `fct_stock_snapshots` | Valeur brute multipliée par un taux selon l'ancienneté : 0 % si sorti dans les 12 derniers mois et couverture d'un an au plus ; 50 % si aucune sortie depuis 12 à 24 mois ou couverture de plus d'un an ; 100 % si aucune sortie depuis plus de 24 mois | Hypothèse (grille par ancienneté, pratique courante) | Direction financière |
| Stock dormant | `fct_stock_snapshots` | Aucune sortie depuis 12 mois, ou couverture supérieure à un an | Hypothèse | Supply chain, direction financière |
| Taux de correspondance | `fct_sales_lines` | Part du CA rapproché entre systèmes (pondérée par le CA), en plus de la part de lignes ; lignes en cause consultables | Hypothèse | Direction informatique |
| Doublons de bascule | `fct_sales_lines` | Nombre et montant des transactions présentes dans les deux ERP, selon `map_transactions` (section 4) | Hypothèse | Direction informatique |

**Les conventions communes à toutes les tables :**

- **Quantités** : toujours exprimées en unité de base (paire ou pièce), converties dès la couche de staging.
- **Devises** : taux moyens mensuels calculés à partir des taux de référence quotidiens de la BCE. Le dirham des Émirats (AED), absent des taux BCE, est converti via le dollar, grâce à son taux d'arrimage fixe.
- **Ventes entre filiales** : repérées par un indicateur sur les lignes de commande et de vente (`is_intercompany`), et exclues du CA consolidé. Un client qui est lui-même une entité du groupe le dit dans le référentiel client, avec l'entité correspondante : c'est ainsi qu'on connaît l'entité qui achète.

**Trois règles de calcul complémentaires :**

- **Le pont du carnet de commandes**, contrôle de cohérence mensuel : carnet de fin de mois = carnet de début de mois + prises de commandes − montants expédiés − annulations. Un écart signale un problème de données. Il évite aussi un piège classique : les commandes du mois moins le CA du mois ne donnent pas les commandes non livrées, car le CA d'un mois vient aussi de commandes plus anciennes.
- **Le stock est une mesure semi-additive.** On additionne les stocks de plusieurs articles ou plateformes à une même date, mais jamais les fins de mois entre elles. Sur une période, on prend la valeur de fin de période, ou une moyenne des fins de mois.
- **La valeur du stock = quantité × coût unitaire.** Le coût unitaire est celui que fournit l'ERP pour chaque article et chaque mois, supposé calculé au coût moyen pondéré : la moyenne des coûts d'achat, pondérée par les quantités achetées. Le projet l'utilise tel quel ; le recalculer à partir des achats fournisseurs est une extension. Valeur nette = valeur brute − dépréciation.
- **Un seul coût unitaire pour tout le projet : le coût groupe de l'article.** La filiale qui revend une marchandise achetée à une plateforme du groupe enregistre dans son ERP un coût égal au prix interne (6 € dans l'exemple ci-dessous) : ce coût n'est jamais utilisé. La marge brute comme la valeur du stock utilisent le coût groupe de l'article pour le mois, tel que le fournit la fiche article de l'ERP.
- **Le stock est valorisé au coût d'origine pour le groupe**, c'est-à-dire au coût d'achat ou de fabrication auprès de l'extérieur, jamais au prix de vente interne. Une marchandise vendue 6 € par la plateforme chinoise à la filiale allemande, qui l'avait payée 4 € à un fournisseur, reste à 4 € dans le stock du groupe : la marge interne de 2 € n'existe pour le groupe qu'une fois la marchandise revendue à un client extérieur.
- **Le stock se suit en unités et en valeur.** La valeur peut bouger sans que les quantités changent (coûts d'achat, change, mix des articles, dépréciations) : les deux mesures sont toujours affichées ensemble.

## 3. Pourquoi ces règles ont du sens pour Delta Plus

Une règle sans justification ne se défend pas. Voici, pour chaque choix qui n'est pas imposé, ce qui le rend cohérent avec la situation de Delta Plus : un groupe qui vend surtout à des distributeurs, depuis des plateformes logistiques, avec un stock lourd et une migration ERP en cours.

**Le CA à la date de facture, avec une facture émise à l'expédition (appuyé par Delta Plus, puis hypothèse).** La norme IFRS 15 reconnaît le CA quand le client prend le contrôle des biens, ce qui dépend des conditions de vente. Les conditions générales de vente publiées par Delta Plus (version de 2022, pour sa division Systèmes) fixent des prix départ usine (*ex-works*) et un transfert des risques dès l'expédition depuis leurs entrepôts ; les marchandises voyagent ensuite aux risques du client, par transporteur. Le moment clé est donc l'expédition. Il reste une hypothèse : que la facture parte le jour même, ce qui est le fonctionnement habituel d'un ERP pour un fournisseur qui expédie depuis ses plateformes. Les conditions peuvent différer selon les filiales ou les grands distributeurs (port payé, par exemple) : à vérifier.

**Le taux moyen du mois plutôt que le taux du jour (pratique courante).** Pour consolider, les groupes convertissent le compte de résultat de leurs filiales étrangères au taux moyen de la période, et le bilan au taux de clôture. Utiliser le taux moyen mensuel rapproche notre CA de la méthode de consolidation, lisse le bruit des variations quotidiennes et rend le calcul de la croissance organique simple : le même mois, aux taux moyens de l'année précédente.

**L'exclusion des ventes entre filiales (norme).** Le CA consolidé, c'est le groupe vu comme une seule entreprise : on ne compte que ce qu'il vend à l'extérieur. Si la plateforme chinoise vend une paire de gants 6 € à la filiale française, qui la revend 10 € à un distributeur, l'addition des deux filiales donne 16 €, mais le groupe n'a vendu qu'une paire, pour 10 € : la vente interne de 6 € est éliminée (IFRS 10). Chez Delta Plus, l'enjeu est massif. Le rapport semestriel 2026 indique environ 104 M€ de ventes entre secteurs, pour 196 M€ de CA consolidé : sans élimination, le CA affiché serait d'environ 300 M€. Et ce n'est qu'un minimum. Delta Plus découpe son activité en secteurs géographiques (Europe et hors Europe) : les 104 M€ sont les ventes d'un secteur à l'autre, par exemple de la Chine vers l'Europe. Les ventes internes à l'intérieur d'un même secteur, par exemple de la France vers l'Allemagne, ne sont pas dans ce chiffre. Le total des ventes internes est donc d'au moins 104 M€.

**Le CA d'une filiale, c'est sa contribution au CA consolidé (pratique courante).** Une filiale a deux chiffres d'affaires possibles. Son CA « propre », celui de ses comptes, inclut ses ventes aux autres filiales. Sa contribution au CA consolidé ne garde que ses ventes aux clients extérieurs. Le projet utilise la contribution : la somme des filiales retombe alors exactement sur le CA du groupe, et une plateforme qui ne vend qu'aux autres filiales apparaît avec un CA proche de zéro, sa valeur se lisant dans les marges des filiales qui revendent. Une vente est repérée comme interne quand son client est lui-même une entité du groupe (`is_intercompany` sur la ligne de vente).

**La marge brute sur le coût d'achat des marchandises vendues (Delta Plus).** C'est la définition qui ressort de leur compte de résultat : CA moins coût d'achat des marchandises vendues, le transport étant classé plus bas, dans les charges variables. On prend le coût en vigueur à la date de la vente pour pouvoir expliquer une baisse de marge par un effet coût, prix, mix ou change.

**L'OTIF mesuré à l'expédition, par rapport à la date promise (hypothèse appuyée).** Delta Plus ne publie pas d'indicateur de taux de service. Dans ses conditions générales de vente, la livraison se fait par remise à un transporteur, et les délais de livraison sont « donnés à titre indicatif » : Delta Plus ne livre pas lui-même et maîtrise surtout la date d'expédition. La date de réception chez le client est connue du transporteur, pas de l'ERP ; mesurer à l'expédition évite de dépendre d'une donnée absente. En extension, les données de suivi des transporteurs (preuve de livraison) permettraient un OTIF à la réception. La date promise est l'engagement de Delta Plus : c'est ce qui mesure sa propre fiabilité. La variante à la date demandée par le client est calculée aussi, car c'est elle que vit le distributeur.

**Comment se calcule l'OTIF, sur un exemple.** Une commande passe par trois dates : la date demandée par le client (« livrez-moi pour le 20 mars »), la date promise par Delta Plus dans son accusé de réception (« nous expédierons le 18 mars »), et la date d'expédition réelle. L'OTIF mesure l'écart entre la promesse et l'expédition, c'est-à-dire la fiabilité de Delta Plus. Quatre lignes de commande promises en mars :

| Ligne | ordered_quantity | first_promised_date | Expéditions (`shipped_date`, `shipped_quantity`) | À l'heure | En totalité | OTIF |
| --- | --- | --- | --- | --- | --- | --- |
| A | 100 | 18 mars | 100 le 17 mars | oui | oui | oui |
| B | 100 | 18 mars | 60 le 18 mars, puis 40 le 28 mars | non | oui | non |
| C | 50 | 20 mars | 50 le 25 mars | non | oui | non |
| D | 80 | 25 mars | 70 le 24 mars, le reste annulé | oui | non | non |

OTIF de mars = 1 ligne sur 4, soit 25 %. Décomposer en « à l'heure » et « en totalité » dit pourquoi : B et C sont des retards, D un manque de quantité, peut-être une rupture.

**L'écart de promesse, un signal d'alerte précoce.** L'OTIF mesure si Delta Plus tient sa parole ; l'écart entre la date demandée et la date promise mesure ce qu'il promet. Si Delta Plus promet de plus en plus souvent plus tard que ce que le client demande, il manque de stock ou de capacité, et on le voit avant que l'OTIF ne baisse : un OTIF stable peut cacher une dégradation, du type « on tient nos promesses, mais on promet de plus en plus tard ».

**Pourquoi l'OTIF est rattaché aux lignes de commande, et non aux expéditions.** Une ligne jamais expédiée n'a aucune ligne dans `fct_deliveries` : si l'OTIF y était calculé, elle disparaîtrait. On le calcule donc sur `fct_order_lines`, où chaque ligne reçoit, depuis les expéditions, sa date de dernière expédition et sa quantité totale expédiée.

Trois choix à savoir justifier. **Le dénominateur, ce sont les lignes promises dans la période**, et non celles expédiées : sinon, une ligne jamais expédiée sortirait du calcul alors que c'est le pire échec. **On garde la première date promise** : si la promesse est repoussée en cours de route, la nouvelle date ne compte pas, sinon il suffirait de décaler la promesse pour être toujours à l'heure. **Une expédition en avance compte comme à l'heure** (hypothèse) : certaines entreprises la comptent comme un échec, car le distributeur doit stocker et payer plus tôt ; McKinsey cite par exemple une tolérance d'un seul jour d'avance.

**Le client actif à 12 mois (hypothèse).** Un distributeur d'EPI commande régulièrement, mais avec une saisonnalité (chantiers, budgets annuels des entreprises clientes). Une fenêtre de 12 mois couvre un cycle complet de saisons : un client qui n'a rien commandé depuis un an est réellement inactif, pas seulement en creux saisonnier.

**Le stock dormant à 12 mois sans sortie ou à plus d'un an de couverture (hypothèse).** Dans la littérature, un stock à rotation lente se situe souvent entre 90 et 180 jours sans mouvement, mais le seuil dépend du secteur. Les EPI ne se périment pas vite et restent longtemps au catalogue ; et la couverture normale du groupe est déjà élevée, d'environ 8 mois (118 M€ de stock pour environ 171 M€ de coût d'achat des marchandises vendues par an). Un seuil à un an désigne donc ce qui sort nettement de la normale du groupe, sans signaler à tort des produits simplement lents.

**La couverture sur trois mois de sorties, en volume et en valeur (pratique courante).** Trois mois lissent les à-coups d'une semaine ou d'un mois, tout en restant assez récents pour refléter une baisse de la demande. Mais une moyenne réagit en retard : un article vendu 90, puis 60, puis 30 a une couverture moyenne qui sous-estime la réalité ; c'est pourquoi la couverture est toujours affichée avec l'évolution des ventes. En volume, la couverture n'a de sens que pour un article (on n'additionne pas des gants et des casques). Dès qu'on regroupe, on passe en valeur au coût : c'est le seul moyen d'additionner des articles différents, et c'est la mesure qui intéresse la finance, car c'est de l'argent immobilisé. À l'échelle du groupe, Delta Plus a environ 8 mois de couverture : 118 M€ de stock au 30 juin 2026 pour environ 171 M€ de coût des marchandises vendues en 2025 (389,6 M€ de CA × 44 %), soit 14,3 M€ par mois.

**Le coût moyen pondéré (hypothèse).** La norme IAS 2 autorise le coût moyen pondéré ou le « premier entré, premier sorti » ; elle interdit le « dernier entré, premier sorti ». Delta Plus ne précise pas sa méthode dans les documents consultés. Le coût moyen pondéré est la méthode la plus répandue dans la distribution, la plus simple à expliquer, et il lisse les variations de prix d'achat, notamment celles du dollar. Le projet prend le coût unitaire tel que l'ERP le fournit, sans le recalculer : c'est ce que fait un analyste dans une entreprise, où le calcul des coûts relève de la comptabilité et de l'ERP. Le recalculer demanderait les achats fournisseurs, qui sont une extension de la question 4.

**La grille de dépréciation par ancienneté (hypothèse).** La norme demande d'inscrire le stock au plus bas entre son coût et ce qu'on peut en tirer en le vendant. En pratique, les distributeurs appliquent une grille de taux selon l'ancienneté ou la rotation, simple à calculer chaque mois sur des milliers d'articles et facile à auditer. Le premier seuil, à 12 mois, est le même que celui du stock dormant : le stock dormant d'aujourd'hui est la dépréciation de demain. Cette grille permet de dire « le stock dormant représente X M€, dont Y M€ déjà dépréciés », le langage d'une direction financière qui veut réduire son stock.

**Les avoirs comptés à leur date d'émission, avec leur type (hypothèse).** Un avoir peut corriger une facture d'un mois précédent : une facture de 1 000 € en décembre, puis un avoir de 100 € en janvier pour des paires abîmées. Le reporting compte l'avoir à sa date d'émission (+ 1 000 € en décembre, − 100 € en janvier) plutôt que de le rattacher à décembre : un mois déjà présenté à la direction ne doit plus bouger. Chaque avoir garde le lien vers sa facture d'origine (`original_invoice_number`) et porte un type (`credit_note_type` : retour, erreur de facturation, remise, ristourne). Le cas sensible est la ristourne de fin d'année : un distributeur qui dépasse un volume d'achat annuel reçoit, par exemple en février, un avoir de 2 % sur ses achats de l'année précédente. La comptabilité l'estime au fil de l'année, mois par mois ; notre reporting la voit d'un coup en février. Le type d'avoir rend cet écart explicable d'un coup d'œil (« c'est la ristourne annuelle, pas une baisse des ventes ») : un écart entre deux chiffres n'est pas forcément une erreur, il peut venir de deux définitions différentes.

**La tolérance de 3 jours dans le rapprochement probable (hypothèse, section 4).** Une commande ressaisie à la main pendant la migration garde en principe la date demandée par le client, mais une saisie peut l'arrondir ou la décaler de quelques jours, par exemple au jour ouvré suivant. Trois jours couvrent ces écarts de saisie sans rapprocher à tort deux commandes réellement différentes, qui seraient en général espacées d'au moins une semaine chez un même distributeur.

## 4. Le rapprochement des transactions migrées

Lors de la bascule du 7 avril 2026, les commandes encore ouvertes ont été recréées dans le nouvel ERP. Une même vente peut donc exister dans les deux systèmes, sous deux numéros, deux codes client et deux codes article. Rapprocher les produits et les clients ne suffit pas : deux commandes différentes peuvent porter sur le même produit, pour le même client, au même prix.

La table `map_transactions` relie chaque commande de l'ancien ERP à son équivalent dans le nouveau.

| Colonne | Contenu |
| --- | --- |
| `entity_id` | La filiale concernée |
| `legacy_order_number` | Numéro dans l'ancien ERP |
| `m3_order_number` | Numéro dans le nouvel ERP |
| `match_status` | `certain`, `probable` ou `unmatched` |
| `match_rule` | La règle qui a produit le rapprochement |

**Les trois statuts, sur un exemple.** La commande 45872 de l'ancien ERP (client C0042, article GNT-204, 200 paires demandées pour le 15 avril) est recréée dans le nouvel ERP sous le numéro 1000123 (client 10042, article HAND-000204).

| Statut | Règle | Dans l'exemple |
| --- | --- | --- |
| `certain` | Le champ de référence de migration du nouvel ERP contient l'ancien numéro | Le champ indique 45872 |
| `probable` | Même client et même article (via les tables de correspondance), même quantité restant à livrer, date demandée identique à 3 jours près | Le champ est vide, mais C0042 = 10042, GNT-204 = HAND-000204, 200 paires, même date demandée |
| `unmatched` | Aucune commande équivalente trouvée | Commande annulée, mal ressaisie ou pas encore migrée |

**Pourquoi on ne compare ni la date de commande ni la quantité commandée.** Dans le nouvel ERP, la date de commande est souvent celle de la migration, pas celle d'origine. Et seule la quantité restant à livrer est migrée : si 50 paires étaient parties avant la bascule, le nouvel ERP n'en contient que 150.

| Règle | Source | À valider avec |
| --- | --- | --- |
| Conserver une référence explicite entre l'ancien et le nouveau numéro | Pratique courante (bonne pratique de migration) | Équipe de migration |
| Tolérance de 3 jours sur la date demandée | Hypothèse | Équipe de migration |
| Les transactions `certain` et `probable` ne sont comptées qu'une fois, avec la version du nouvel ERP après le 7 avril 2026 | Hypothèse | Direction informatique, direction financière |
| Les transactions `unmatched` restent comptées, mais elles sont signalées et listées sur la page qualité, jamais supprimées en silence | Hypothèse | Direction informatique |
| Un test dbt vérifie que chaque transaction ne contribue qu'une fois au CA consolidé | Pratique courante | — |

## 5. Le journal de réconciliation

Un journal mensuel, par filiale, explique le passage des totaux bruts des sources au chiffre d'affaires consolidé. C'est le pont qu'une direction informatique ou financière veut voir pour faire confiance aux chiffres.

| Colonne | Contenu |
| --- | --- |
| `month_start_date`, `entity_id` | Le mois et la filiale |
| `source_total_amount_eur` | Total des lignes de facture et d'avoir de toutes les sources |
| `migration_duplicates_amount_eur` | Moins les doublons de migration (`certain` et `probable`) |
| `intercompany_sales_amount_eur` | Moins les ventes entre filiales |
| `test_and_rejected_amount_eur` | Moins les lignes de test et les lignes rejetées par les contrôles |
| `consolidated_revenue_amount_eur` | Égale le CA consolidé |
| `residual_gap_amount_eur` | L'écart entre ce calcul et le CA des modèles finaux, qui doit être nul |

Tout écart résiduel non nul fait échouer un test et renvoie vers les lignes en cause. L'écart est suivi de près autour de la bascule (mars à mai 2026).

**Le rapprochement intercompagnie (extension)**, contrôle complémentaire : pour chaque mois et chaque couple d'entités, les ventes déclarées par l'entité qui vend (la plateforme chinoise vers la France, par exemple) sont comparées aux achats déclarés par l'entité qui achète (la France auprès de la plateforme chinoise). Un écart vient d'une erreur, d'un oubli ou d'un décalage dans le temps : une marchandise facturée fin juin par la plateforme et reçue en juillet par la filiale est du stock en transit. Pendant une migration, ce contrôle est sensible, car les deux entités peuvent être sur deux ERP différents.

## 6. Le protocole à l'aveugle

Pour que les conclusions ne soient pas circulaires, je ne connais pas les histoires cachées dans les données.

1. Claude fixe les histoires dans un fichier scellé, encodé et exclu de Git.
2. L'empreinte SHA-256 du fichier est commitée et poussée sur le dépôt public avant toute analyse : elle prouve que le fichier n'a pas été modifié ensuite.
3. Mes conclusions sont commitées avant l'ouverture du fichier.
4. Le fichier est ensuite publié en clair : chacun peut vérifier l'ordre des étapes.

## 7. Les fichiers de conception

| Fichier | Contenu |
| --- | --- |
| `docs/00_naming_conventions.md` | Les conventions de nommage |
| `docs/01_data_model_and_business_rules.md` | Ce document |
| `docs/02_reference_data.md` et `config/delta_plus/master_data.yml` | Le référentiel maître du groupe fictif |
| `docs/sources/01_legacy_erp.md` | Tables et colonnes de l'ancien ERP, avec leur schéma relationnel |
| `docs/sources/02_m3_export.md` | Tables de l'export de type M3 et correspondance avec les objets métier |
| `docs/sources/03_crm.md` | Structure du document compte du CRM et un exemple JSON |
| `docs/sources/04_spreadsheets.md` | Mise en page du fichier brésilien et du budget |
| `config/delta_plus/defects.yml` | Les types d'effets et les défauts à injecter |

## 8. Idées pour plus tard

Ces idées sont notées pour ne pas les perdre, mais elles ne modifient pas les règles ci-dessus. Elles seront reprises s'il reste du temps, ou citées en entretien comme pistes.

- Le délai de paiement des clients (DSO), si on ajoute les règlements aux sources.
- Un OTIF mesuré à la réception, avec les données de suivi des transporteurs.
- La dépréciation au cas par cas, selon un prix de déstockage, pour les articles retirés du catalogue.
- Le délai d'expédition (jours entre commande et expédition) comme indicateur suivi : il recoupe l'OTIF et l'écart de promesse. Les dates étant disponibles, il reste un outil de diagnostic quand l'OTIF baisse.
- Le stock dans chaque filiale, en plus des plateformes. Il permettrait de voir une plateforme « pousser » du stock vers une filiale qui vend de moins en moins : le stock s'accumule chez la filiale sans que le CA consolidé ne le montre, et la plateforme paraît performante dans ses propres comptes. Avec les achats de chaque filiale, on mesurerait aussi l'intégration d'une filiale rachetée, par la part de ses achats faite auprès du groupe. Ce sont des analyses à forte valeur, mais elles demandent de générer des stocks et des achats par filiale.
- Le recalcul du coût moyen pondéré à partir des achats fournisseurs.
- Les promesses repoussées et leur motif. Compter les lignes dont la date promise a changé, et de combien de jours, donne un signal d'alerte : beaucoup de reports annoncent des difficultés d'approvisionnement. Avec un motif de report (demande du client, retard fournisseur, rupture de stock, autre), on distinguerait les retards subis des reports demandés par le client, qu'il serait injuste de compter comme des échecs de l'OTIF. Conception prévue : dans l'export de type M3 seulement, `reschedule_count` (nombre de reports) et `reschedule_reason_code` (motif du dernier report), rempli de façon partielle comme dans la réalité, où ces champs facultatifs restent souvent vides ; l'ancien ERP n'a pas de motif, si bien que l'analyse n'est possible qu'après la bascule.
- L'écart au budget à taux budget : un budget est construit avec un taux de change supposé (le « taux budget »). Comparer le réalisé au budget au même taux isole la vraie performance d'une filiale, qui ne maîtrise pas les monnaies ; au taux réel, une filiale peut sembler sous son objectif uniquement parce que sa monnaie a baissé.
