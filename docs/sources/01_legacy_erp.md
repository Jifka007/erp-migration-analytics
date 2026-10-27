# Ancien ERP

*Rédigé en phase 1 (conception des sources), tâche 1.2, octobre 2026. Le schéma relationnel est dans [`01_legacy_erp.dbml`](01_legacy_erp.dbml), à coller dans dbdiagram.io pour le dessiner.*

L'ancien ERP est le système historique des filiales. Avant la bascule du 7 avril 2026, il sert toutes les entités sauf le Brésil ; après, il continue de servir l'Espagne, la Chine et les Émirats. Il vit dans une base PostgreSQL du conteneur, `legacy_erp`, et ses tables sont chargées telles quelles dans la couche `raw` (document 00, section 4).

## 1. Ce qu'on simule, et pourquoi

Delta Plus ne nomme pas publiquement son ancien système. Le projet simule donc un ERP ancien **générique**, avec les traits typiques des systèmes de type AS400, sans prétendre reproduire le leur *(hypothèse)*. Il est conçu à partir du fonctionnement d'un ERP (le cycle de la commande à la facture), et non à partir du modèle analytique : c'est l'écart entre les deux qui donne son travail à la couche de staging.

Les traits retenus :

| Trait | Dans l'ancien ERP | Source |
| --- | --- | --- |
| Noms courts et codés, en français | Tables de 6 caractères (`CDEENT` pour « commande, en-tête »), colonnes préfixées par deux lettres propres à leur table (`CENUM`, `LCART`) | Pratique courante des systèmes de type AS400 (noms de 6 à 10 caractères, préfixe par fichier) |
| Dates stockées en nombres | Format `CYYMMDD` : un chiffre de siècle (0 pour 19xx, 1 pour 20xx), puis l'année sur deux chiffres, le mois et le jour. `1260318` = 18 mars 2026 ; `0` = pas de date | Pratique courante des systèmes de type AS400 |
| Texte de longueur fixe | Colonnes `CHAR`, complétées par des espaces à droite ; codes en majuscules, numéros de client complétés par des zéros (`00001042`) | Pratique courante |
| Plusieurs sociétés dans une base | Chaque table de documents commence par le code société (`010`, `030`…) ; un même numéro de commande ou de facture existe dans plusieurs sociétés | Pratique courante des ERP multi-sociétés |
| Peu de contrôles | Aucune clé étrangère imposée par la base : des lignes orphelines sont possibles | Pratique courante |
| L'état actuel, pas l'historique | La date promise est écrasée à chaque report ; le stock n'est photographié qu'à la clôture de chaque mois | Pratique courante |

## 2. Les tables

Onze tables, qui couvrent les ventes et le stock (le cycle de la commande à la facture). Les achats fournisseurs et le journal des mouvements de stock sont des extensions.

| Table | Signification | Préfixe | Une ligne par | Clé |
| --- | --- | --- | --- | --- |
| `SOCIET` | Sociétés | `SO` | société | `SOSOC` |
| `CLIENT` | Fiche client | `CL` | client d'une société | `CLSOC`, `CLCODE` |
| `ARTICL` | Fiche article (catalogue commun au groupe) | `AR` | article | `ARCODE` |
| `COUMOI` | Coût groupe mensuel des articles | `CM` | article et mois | `CMART`, `CMDTCL` |
| `CDEENT` | Commandes, en-têtes | `CE` | commande | `CESOC`, `CENUM` |
| `CDELIG` | Commandes, lignes | `LC` | ligne de commande | `LCSOC`, `LCNUM`, `LCLIG` |
| `BLVENT` | Bons de livraison, en-têtes | `BE` | bon de livraison | `BESOC`, `BENUM` |
| `BLVLIG` | Bons de livraison, lignes | `BL` | ligne de bon de livraison | `BLSOC`, `BLNUM`, `BLLIG` |
| `FACENT` | Factures et avoirs, en-têtes | `FE` | facture ou avoir | `FESOC`, `FENUM` |
| `FACLIG` | Factures et avoirs, lignes | `FL` | ligne de facture ou d'avoir | `FLSOC`, `FLNUM`, `FLLIG` |
| `STKMOI` | Clôture mensuelle du stock | `SM` | article, dépôt et fin de mois | `SMDEPO`, `SMART`, `SMDTCL` |

## 3. Les colonnes

Types : `CHAR(n)` pour le texte de longueur fixe, `NUMERIC(p,s)` pour les nombres (`p` chiffres dont `s` décimales). Les dates sont des `NUMERIC(7,0)` au format `CYYMMDD`.

### `SOCIET` : les sociétés

| Colonne | Type | Signification | Nom cible |
| --- | --- | --- | --- |
| `SOSOC` | CHAR(3) | Code société dans l'ancien ERP : `010` France, `020` Allemagne, `030` Espagne, `040` Chine, `050` Émirats | `entity_id` (par une table de correspondance) |
| `SONOM` | CHAR(30) | Raison sociale | `entity_name` |
| `SODEV` | CHAR(3) | Devise de la société (`EUR`, `CNY`, `AED`) | `currency_code` |
| `SOPAYS` | CHAR(2) | Pays (code ISO) | `country_code` |

Les codes société de l'ancien ERP (`030`) ne sont pas ceux du projet (`ES`) : la correspondance est une table de référence (*seed* dbt), comme dans toute migration.

### `CLIENT` : la fiche client

| Colonne | Type | Signification | Nom cible |
| --- | --- | --- | --- |
| `CLSOC` | CHAR(3) | Société propriétaire de la fiche | `entity_id` |
| `CLCODE` | CHAR(8) | Code client, complété par des zéros (`00001042`) | `customer_code` |
| `CLNOM` | CHAR(40) | Raison sociale | `customer_name` |
| `CLTYPE` | CHAR(3) | Type de client : `DIS` distributeur, `GRP` société du groupe | sert à `is_intercompany` |
| `CLSEGM` | CHAR(3) | Segment : `NEG` négoce BTP et agricole, `SPE` spécialiste EPI, `GEN` généraliste, `GSB` grande surface de bricolage ; vide pour `GRP` | `customer_segment_id` (par correspondance) |
| `CLSOCG` | CHAR(3) | Pour un client `GRP` : la société du groupe qu'il représente | `intercompany_entity_id` |
| `CLPAYS` | CHAR(2) | Pays du client | `country_code` |
| `CLDTCR` | NUMERIC(7,0) | Date de création de la fiche | `created_date` |

Un client appartient à une société : la clé est (`CLSOC`, `CLCODE`). Une vente est interne quand son client est de type `GRP` (voir le document 02, segment `INTERCOMPANY`).

### `ARTICL` : la fiche article

| Colonne | Type | Signification | Nom cible |
| --- | --- | --- | --- |
| `ARCODE` | CHAR(15) | Code article (`GNT204`) | `product_code` |
| `ARLIB` | CHAR(40) | Libellé | `product_name` |
| `ARFAM` | CHAR(4) | Code famille de l'ancien ERP (`GT01`) | `product_family_id` (par correspondance) |
| `ARUNIT` | CHAR(2) | Unité de vente : `PR` paire, `PC` pièce, `BT` boîte | — |
| `ARCOEF` | NUMERIC(5,0) | Nombre d'unités de base dans une unité de vente (une boîte de gants = 10 paires) | sert à convertir les quantités en unité de base |
| `ARSTAT` | CHAR(1) | `A` actif, `S` supprimé du catalogue | `is_active` |

Le catalogue est commun à toutes les sociétés : la fiche article n'a pas de code société.

### `COUMOI` : le coût groupe mensuel

| Colonne | Type | Signification | Nom cible |
| --- | --- | --- | --- |
| `CMART` | CHAR(15) | Code article | `product_code` |
| `CMDTCL` | NUMERIC(7,0) | Date de clôture du mois | `month_end_date` |
| `CMCOUT` | NUMERIC(11,4) | Coût groupe unitaire du mois, en euros, par unité de base : coût moyen pondéré d'achat ou de fabrication pour le groupe | `unit_cost_amount_eur` |

C'est la seule source du coût utilisé pour la marge et la valeur du stock (document 01, section 2 : un seul coût unitaire, le coût groupe). La fiche article ne garde que l'état actuel ; le coût du mois vient de cette table.

### `CDEENT` : les en-têtes de commande

| Colonne | Type | Signification | Nom cible |
| --- | --- | --- | --- |
| `CESOC` | CHAR(3) | Société | `entity_id` |
| `CENUM` | NUMERIC(7,0) | Numéro de commande | `order_number` |
| `CECLI` | CHAR(8) | Code client | `customer_code` |
| `CEDTCD` | NUMERIC(7,0) | Date de commande | `order_date` |
| `CEDEV` | CHAR(3) | Devise de la commande | `currency_code` |
| `CEREF` | CHAR(20) | Référence de commande du client | `customer_reference` |

### `CDELIG` : les lignes de commande

| Colonne | Type | Signification | Nom cible |
| --- | --- | --- | --- |
| `LCSOC` | CHAR(3) | Société | `entity_id` |
| `LCNUM` | NUMERIC(7,0) | Numéro de commande | `order_number` |
| `LCLIG` | NUMERIC(3,0) | Numéro de ligne | `order_line_number` |
| `LCART` | CHAR(15) | Code article | `product_code` |
| `LCQTE` | NUMERIC(11,3) | Quantité commandée, en unité de vente | `ordered_quantity` (convertie en unité de base) |
| `LCPRIX` | NUMERIC(11,4) | Prix unitaire net, en devise de la commande, par unité de vente | `net_unit_price_local` |
| `LCREM` | NUMERIC(5,2) | Remise en pourcentage (`12.50` = 12,5 %), déjà déduite du prix net | `discount_rate` (divisé par 100) |
| `LCDTDM` | NUMERIC(7,0) | Date demandée par le client | `requested_date` |
| `LCDTPR` | NUMERIC(7,0) | Date promise **actuelle** : écrasée à chaque report | `promised_date` |
| `LCDEPO` | CHAR(3) | Site d'expédition prévu : `APT`, `SHA` (plateformes), `DAL`, `DES`, `DEM` (dépôts locaux Allemagne, Espagne, Émirats) | `warehouse_id` (par correspondance) |
| `LCQLIV` | NUMERIC(11,3) | Quantité déjà livrée, cumulée | sert de contrôle |
| `LCQANN` | NUMERIC(11,3) | Quantité annulée | `cancelled_quantity` |
| `LCDTAN` | NUMERIC(7,0) | Date d'annulation ; `0` si aucune | `cancelled_date` |
| `LCSTAT` | CHAR(1) | `O` ouverte, `S` soldée, `A` annulée | `order_line_status` |

**La première date promise n'existe pas dans l'ancien ERP.** Un report écrase `LCDTPR`. Conséquence pour l'OTIF : voir la section 5.

### `BLVENT` : les en-têtes de bon de livraison

| Colonne | Type | Signification | Nom cible |
| --- | --- | --- | --- |
| `BESOC` | CHAR(3) | Société | `entity_id` |
| `BENUM` | NUMERIC(7,0) | Numéro de bon de livraison | `delivery_number` |
| `BECLI` | CHAR(8) | Client livré | `customer_code` |
| `BEDEPO` | CHAR(3) | Site d'expédition (mêmes codes que `LCDEPO`) | `warehouse_id` (par correspondance) |
| `BEDTEX` | NUMERIC(7,0) | Date d'expédition | `shipped_date` |
| `BETRAN` | CHAR(10) | Code transporteur | `carrier_code` |

### `BLVLIG` : les lignes de bon de livraison

| Colonne | Type | Signification | Nom cible |
| --- | --- | --- | --- |
| `BLSOC` | CHAR(3) | Société | `entity_id` |
| `BLNUM` | NUMERIC(7,0) | Numéro de bon de livraison | `delivery_number` |
| `BLLIG` | NUMERIC(3,0) | Numéro de ligne du bon | `delivery_line_number` |
| `BLCDE` | NUMERIC(7,0) | Numéro de la commande livrée | `order_number` |
| `BLCLIG` | NUMERIC(3,0) | Ligne de la commande livrée | `order_line_number` |
| `BLART` | CHAR(15) | Code article | `product_code` |
| `BLQTE` | NUMERIC(11,3) | Quantité expédiée, en unité de vente | `shipped_quantity` (convertie en unité de base) |

C'est `BLCDE` et `BLCLIG` qui relient une expédition à sa ligne de commande : une ligne de commande livrée en deux fois a deux lignes de bon de livraison.

### `FACENT` : les en-têtes de facture et d'avoir

| Colonne | Type | Signification | Nom cible |
| --- | --- | --- | --- |
| `FESOC` | CHAR(3) | Société | `entity_id` |
| `FENUM` | NUMERIC(7,0) | Numéro de facture ou d'avoir (même numérotation) | `invoice_number` |
| `FETYPE` | CHAR(1) | `F` facture, `A` avoir | `is_credit_note` |
| `FECLI` | CHAR(8) | Client facturé | `customer_code` |
| `FEDTFA` | NUMERIC(7,0) | Date de facture | `invoice_date` |
| `FEDEV` | CHAR(3) | Devise | `currency_code` |
| `FEORIG` | NUMERIC(7,0) | Pour un avoir : la facture d'origine ; `0` sinon | `original_invoice_number` |
| `FEMOTI` | CHAR(3) | Pour un avoir : `RET` retour, `RIS` ristourne, `PRX` erreur de prix | `credit_note_type` |

### `FACLIG` : les lignes de facture et d'avoir

| Colonne | Type | Signification | Nom cible |
| --- | --- | --- | --- |
| `FLSOC` | CHAR(3) | Société | `entity_id` |
| `FLNUM` | NUMERIC(7,0) | Numéro de facture ou d'avoir | `invoice_number` |
| `FLLIG` | NUMERIC(3,0) | Numéro de ligne | `invoice_line_number` |
| `FLBL` | NUMERIC(7,0) | Bon de livraison facturé ; `0` pour un avoir sans retour (ristourne) | `delivery_number` |
| `FLBLLG` | NUMERIC(3,0) | Ligne du bon de livraison facturée | `delivery_line_number` |
| `FLART` | CHAR(15) | Code article | `product_code` |
| `FLQTE` | NUMERIC(11,3) | Quantité, en unité de vente, **toujours positive** | `quantity` (signée selon `FETYPE`, convertie en unité de base) |
| `FLMTHT` | NUMERIC(13,2) | Montant hors taxes en devise, **toujours positif** | `net_amount_local` (signé selon `FETYPE`) |
| `FLPRV` | NUMERIC(11,4) | Prix de revient unitaire enregistré par la société | **jamais utilisé** |

Deux pièges à connaître :

- **Les montants d'avoir sont positifs** : c'est `FETYPE = 'A'` qui dit qu'il faut les soustraire. Une somme naïve de `FLMTHT` ajoute les avoirs au CA au lieu de les retirer.
- **`FLPRV` est le coût de la filiale**, c'est-à-dire le prix interne auquel elle a acheté au groupe. Le projet utilise toujours le coût groupe de `COUMOI` (document 01, section 2).

### `STKMOI` : la clôture mensuelle du stock

| Colonne | Type | Signification | Nom cible |
| --- | --- | --- | --- |
| `SMDEPO` | CHAR(3) | Plateforme : `APT` ou `SHA` (les dépôts locaux n'ont pas de stock suivi) | `warehouse_id` (par correspondance) |
| `SMART` | CHAR(15) | Code article | `product_code` |
| `SMDTCL` | NUMERIC(7,0) | Date de clôture (dernier jour du mois) | `month_end_date` |
| `SMQTE` | NUMERIC(13,3) | Quantité en stock, en unité de base | `stock_quantity` |

L'ERP ne sait pas quel était le stock à une date passée : il garde une photo des quantités à chaque clôture mensuelle, comme pour la comptabilité. La valeur se calcule avec le coût groupe du mois (`COUMOI`) : une seule source de coût pour la marge et le stock. Le dépôt d'Apt n'est dans l'ancien ERP que jusqu'à la clôture de mars 2026 ; ensuite, il est dans M3. Le dépôt de Shanghai y reste sur toute la période. La dépréciation et la date de dernière sortie ne sont pas dans l'ERP : elles sont calculées dans dbt (document 01, section 2).

## 4. Une vente suivie de bout en bout

La filiale espagnole (`030`) reçoit une commande de 100 paires de gants anti-coupure du distributeur `00001042`, le 3 mars 2026. Elle les expédie depuis son dépôt local (`DES`). Les 100 paires sont promises pour le 18 mars ; la date est ensuite repoussée au 25 mars. 60 paires partent le 18, 40 le 28. Cinq paires reviennent abîmées le 10 avril.

`CDEENT` et `CDELIG` :

| CESOC | CENUM | CECLI | CEDTCD | CEDEV |
| --- | --- | --- | --- | --- |
| 030 | 45872 | 00001042 | 1260303 | EUR |

| LCSOC | LCNUM | LCLIG | LCART | LCQTE | LCPRIX | LCDTDM | LCDTPR | LCQLIV | LCSTAT |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 030 | 45872 | 1 | GNT204 | 100.000 | 10.0000 | 1260320 | 1260325 | 100.000 | S |

La date promise affiche le 25 mars : le 18 mars, première promesse, a disparu.

`BLVENT` et `BLVLIG` :

| BLSOC | BLNUM | BLLIG | BLCDE | BLCLIG | BLART | BLQTE |
| --- | --- | --- | --- | --- | --- | --- |
| 030 | 901 | 1 | 45872 | 1 | GNT204 | 60.000 |
| 030 | 934 | 1 | 45872 | 1 | GNT204 | 40.000 |

(`BEDEPO` vaut `DES` ; `BEDTEX` vaut `1260318` pour le bon 901 et `1260328` pour le bon 934.)

`FACENT` et `FACLIG` :

| FESOC | FENUM | FETYPE | FECLI | FEDTFA | FEORIG | FEMOTI |
| --- | --- | --- | --- | --- | --- | --- |
| 030 | 5001 | F | 00001042 | 1260318 | 0 | |
| 030 | 5043 | F | 00001042 | 1260328 | 0 | |
| 030 | 5077 | A | 00001042 | 1260410 | 5043 | RET |

| FLSOC | FLNUM | FLLIG | FLBL | FLBLLG | FLART | FLQTE | FLMTHT |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 030 | 5001 | 1 | 901 | 1 | GNT204 | 60.000 | 600.00 |
| 030 | 5043 | 1 | 934 | 1 | GNT204 | 40.000 | 400.00 |
| 030 | 5077 | 1 | 0 | 0 | GNT204 | 5.000 | 50.00 |

L'avoir 5077 a un montant positif : c'est `FETYPE = 'A'` qui le rend négatif dans `fct_sales_lines`.

**Ce que la staging devra faire** pour passer de ces tables à nos tables de faits : traduire les noms, convertir les dates `CYYMMDD`, retirer les espaces des codes, remplacer les codes société, dépôt, famille et segment par ceux du projet, convertir les quantités en unité de base, signer les avoirs, et joindre les lignes à leurs en-têtes sur la société **et** le numéro.

## 5. La conséquence pour l'OTIF

L'ancien ERP ne garde que la dernière date promise, alors que M3 garde les versions successives d'une ligne de commande et donc la première promesse. Si l'on mesurait l'OTIF sur la dernière promesse avant la bascule, puis sur la première après, l'OTIF de la France et de l'Allemagne chuterait le 7 avril sans que le service ait changé : seule la règle de mesure aurait changé. Le projet calcule donc deux OTIF (document 01, section 2) :

- **l'OTIF officiel**, sur la première promesse, disponible là où elle existe (M3) ;
- **l'OTIF comparable**, sur la dernière promesse, disponible partout, qui sert aux comparaisons dans le temps et entre systèmes, notamment autour de la bascule.

Un *snapshot* dbt quotidien des lignes de commande ouvertes de l'ancien ERP permet, à partir de sa mise en place, de garder la première promesse pour les entités restées sur l'ancien système.

## 6. Ce qui n'est pas dans ce document

- Les défauts injectés dans les données (doublons, codes manquants, lignes orphelines, fiches client mal typées) : tâche 1.6, `config/delta_plus/defects.yml`.
- Les commandes ouvertes recréées dans M3 à la bascule, et leur rapprochement : document 01, section 4.
- Les achats fournisseurs et le journal des mouvements de stock : extensions.

## Sources

- [MC Press, conventions de nommage des fichiers sur IBM i](https://www.mcpressonline.com/programming/rpg/rpg-academy-write-better-code-naming-conventions-for-physical-and-logical-files)
- [Nick Litten, les formats de date sur IBM i et AS400](https://www.nicklitten.com/how-to-compare-100-year-date-to-a-timestamp-aka-weird-as400-iseries-date-formats/)
- [Infor, versions des données dans le Data Lake (variation ID)](https://docs.infor.com/inforos/2026.x/en-us/useradminlib_cloud/datafabrug/msq1664800989640.html)
