# Fichier de la filiale brésilienne

*Rédigé en phase 1 (conception des sources), tâche 1.5, octobre 2026.*

La filiale brésilienne est entrée dans le groupe le 1er janvier 2026 et garde ses propres outils *(choix du projet, calé sur les acquisitions de Delta Plus en Amérique latine, dont Athenas au Brésil)*. Le groupe ne reçoit d'elle qu'un **export mensuel de ses ventes**, envoyé par sa comptabilité. C'est la source la plus fragile du projet : un fichier Excel préparé à la main, dans une autre langue, une autre devise et avec d'autres codes.

## 1. Ce qu'on simule, et pourquoi

**Un fichier Excel par mois** (`vendas_2026_03.xlsx`), comme une comptabilité qui clôture et envoie chaque mois *(pratique courante)*. Les fichiers sont déposés dans un dossier lisible par Airbyte (emplacement choisi en phase 3).

**Des lignes de facture, et rien d'autre** : ni commandes, ni expéditions, ni stock (document 01, section 1). Le Brésil compte donc dans le CA, la marge et la croissance, mais pas dans l'OTIF, le carnet ni le stock : c'est une limite assumée, et un argument pour son intégration.

**Ce que le fichier doit permettre de mesurer** : l'intégration de la filiale (question 5), c'est-à-dire la part de son chiffre d'affaires réalisée en références du groupe. Tant qu'elle vend ses propres produits, le groupe ne capte pas la marge de ses usines ; quand elle vend des produits du groupe, achetés à la plateforme de Shanghai, il la capte (document 02, section 2).

## 2. La mise en page d'un fichier

Une seule feuille, `Vendas`. Comme dans beaucoup de fichiers préparés à la main, le tableau ne commence pas en première ligne :

| Ligne | Contenu |
| --- | --- |
| 1 | Titre : `Relatório de vendas – Delta Brasil` |
| 2 | Période : `Março de 2026` |
| 3 | Vide |
| 4 | En-têtes de colonnes, en portugais |
| 5 et suivantes | Une ligne par ligne de facture ou de devolução (avoir) |
| Dernière ligne | `Total` : la somme des montants, à exclure du chargement |

## 3. Les colonnes

| Colonne (portugais) | Traduction | Format | Nom cible |
| --- | --- | --- | --- |
| `Número da nota fiscal` | Numéro de facture (la *nota fiscal* est la facture électronique brésilienne) | Texte (`NF-000318`) | `invoice_number` |
| `Item` | Numéro de ligne de la facture | Entier | `invoice_line_number` |
| `Data de emissão` | Date d'émission | `DD/MM/AAAA` (`18/03/2026`), parfois une date Excel | `invoice_date` |
| `Tipo` | `Venda` (vente), `Devolução` (retour) ou `Cancelada` (*nota fiscal* annulée après émission, à exclure) | Texte | `is_credit_note` ; une devolução a le type d'avoir `RET` (`credit_note_type`), le Brésil n'émet pas de ristournes dans le fichier |
| `Nota fiscal de origem` | Pour une devolução : la facture d'origine | Texte, souvent vide | `original_invoice_number` |
| `Código do cliente` | Code client du Brésil | Texte (`C-2210`) | `customer_code` |
| `Nome do cliente` | Raison sociale | Texte | `customer_name` |
| `UF` | État brésilien du client (`SP`, `RJ`…) ; non utilisé dans le cœur | Texte | `region_code` |
| `Segmento` | Segment, avec les mots du Brésil (`Revenda construção`, `Distribuidor EPI`…) | Texte | `customer_segment_id` (par correspondance) |
| `Código do produto` | Code article du Brésil (`ATH-5521`) | Texte | `local_product_code` |
| `Descrição` | Libellé | Texte | `product_name` |
| `Referência Delta Plus` | Pour un produit du groupe : sa référence groupe ; vide pour un produit local, et parfois vide à tort | Texte | sert à `map_products` |
| `Unidade` | Unité de vente : `PAR` (paire), `PC` (pièce), `CX` (boîte) | Texte | sert à la conversion |
| `Quantidade` | Quantité, en unité de vente ; positive même pour une devolução | Nombre | `invoiced_quantity` (signée selon `Tipo`, convertie en unité de base) |
| `Valor líquido (R$)` | Montant net hors taxes, en réals ; positif même pour une devolução | Texte au format brésilien (`1.234,56`) ou nombre | `net_amount_local` (signé selon `Tipo`) |
| `Custo unitário (R$)` | Coût moyen unitaire de la filiale, en réals | Texte au format brésilien ou nombre | utilisé **seulement pour les produits locaux** |

La devise est toujours le réal (`BRL`), jamais écrite ligne par ligne. **Le coût suit la règle du coût groupe** (document 01, section 2) : pour un produit du groupe, le coût de la filiale est le prix interne payé à Shanghai et n'est jamais utilisé ; on prend le coût groupe (`COUMOI`). Pour un produit local, il n'y a pas de coût groupe : on prend le coût moyen de la filiale (`Custo unitário`), qui est alors le coût d'origine pour le groupe.

## 4. Produits du groupe et produits locaux

Le système du Brésil crée **ses propres codes**, même pour les produits du groupe. La référence du groupe n'apparaît que dans la colonne `Referência Delta Plus`, remplie à la main. Le rattachement se fait en trois étapes :

1. `Referência Delta Plus` est remplie et existe dans le catalogue du groupe : produit du groupe (statut `certain`), rattaché à son identifiant unifié par `map_products`. La référence peut être un code de l'ancien ERP (le Brésil achète à Shanghai, restée sur l'ancien système) ou de M3 : `map_products` les ramène au même article.
2. La colonne est vide, mais le code brésilien figure dans une table de correspondance tenue à la main (`seed_brazil_products`) : produit du groupe (statut `probable`).
3. Sinon : **produit local**, hérité d'avant le rachat. Il entre dans `dim_product` avec le type `local` (le cadrage prévoit ce type de référence).

**Chaque produit local a une gamme, et une conversion d'unité.** La table tenue à la main (`seed_brazil_products`) donne, pour chaque code brésilien local, sa gamme (obligatoire : le budget et les analyses se lisent par gamme), sa famille quand elle est connue, et le nombre d'unités de base dans une boîte (`CX`). Pour un produit du groupe, la conversion vient de la fiche article du groupe. Un code local absent de la table est signalé, avec la gamme `UNK`.

**L'indicateur d'intégration** : la part du CA du Brésil réalisée en produits du groupe, mois par mois. Elle doit monter. Elle se lit avec la part de ses achats faite auprès du groupe (ventes internes de Shanghai au Brésil) : si la première monte sans la seconde, il y a une incohérence à investiguer.

## 5. Les pièges d'un fichier Excel, et leur traitement

| Piège | Traitement dans la staging |
| --- | --- |
| Lignes de titre au-dessus du tableau, ligne `Total` en bas | Lecture à partir de la ligne 4 ; la ligne `Total` est exclue et sert de **contrôle** : la somme des lignes doit lui être égale |
| Dates en texte `DD/MM/AAAA` ou en date Excel | Conversion selon le type, test de valeur non nulle |
| Montants au format brésilien (point pour les milliers, virgule pour les décimales) | Conversion numérique, test de valeur non nulle |
| Devoluções en valeurs positives | Signées selon `Tipo` |
| Boîtes (`CX`) | Converties en unité de base |
| Un mois manquant, ou envoyé deux fois | Contrôle : un fichier et un seul par mois depuis janvier 2026 ; un doublon de fichier est détecté par le nom et par le numéro de *nota fiscal* |
| Un mois renvoyé corrigé (`vendas_2026_03_v2.xlsx`) | La version la plus récente remplace l'ancienne, ligne à ligne par numéro de *nota fiscal* et d'item ; l'ancienne est gardée dans `raw` pour la traçabilité |
| *Nota fiscal* annulée (`Cancelada`) | Exclue du CA, comptée et listée sur la page qualité |
| Retour arrivé le mois suivant | Normal : la devolução est dans le fichier du mois où elle est émise, avec sa facture d'origine |
| Référence Delta Plus vide ou fausse | Table de correspondance tenue à la main, taux de correspondance suivi sur la page qualité |

Les taux de ces défauts sont fixés en tâche 1.6 (`config/delta_plus/defects.yml`).

## 6. Les clients

Le Brésil a ses propres codes clients, sans équivalent dans les autres systèmes et sans compte dans le CRM. L'identifiant unifié est le code brésilien précédé de l'entité (`BR-C-2210`). Le segment est ramené aux segments du groupe par une table de correspondance. Il n'y a pas de client interne : le Brésil ne vend pas aux autres entités.

## 7. Ce que le Brésil ne permet pas de calculer

Sans commandes ni expéditions, le Brésil n'entre ni dans l'OTIF, ni dans le carnet, ni dans les prises de commandes. Il n'entre pas non plus dans les **clients actifs**, définis sur les lignes de commande (document 01) : ses clients sont comptés à part, à partir de ses factures, et signalés comme tels. Ses ventes ne sont rattachées à aucune ligne de commande ni expédition (`order_number` et `delivery_number` vides), ce qui est attendu et ne compte pas comme une anomalie.

## 8. Les montants en euros

Comme toutes les ventes, les montants sont convertis au taux moyen BCE du mois de la facture (EUR → BRL, publié directement par la BCE). Pour la croissance organique, le Brésil compte dans l'**effet de périmètre** de janvier à décembre 2026, puisqu'il est entré dans le groupe le 1er janvier (document 01, section 2).

## Sources

- [Delta Plus, acquisition d'Athenas au Brésil (communiqué)](https://media.deltaplus.eu/asset/db150d9f-3938-48a6-a365-712c2aea1032/Financial-press-release-Acquisition-Athenas-EN.pdf)
