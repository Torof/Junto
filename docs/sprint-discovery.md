# Discovery — Spécification (modèle « dispos »)

> **Statut : modèle + design décidés, non construits.** Réflexion 2026-07-28, design/maquettes 2026-07-29 (Scott).
> Prochaine étape = **décider go / no-go** (la feature est-elle utile ?), puis valider les chaînes d'autorisation, puis build.
> Aucune migration ni code à ce jour. Maquettes de référence : voir « Design validé — maquettes ».
>
> ⚠️ Ce document **remplace** l'ancienne spec « Partenaires + Demandes » (annuaire de
> profils, option A), **abandonnée** : elle inversait le but de Junto et glissait vers
> le dating / la chasse aux profils. L'historique reste dans `git log`.

---

## 1. Le problème que ça résout

La carte est faite pour de l'**épars et du précis** (des activités dispersées, à un point de RDV, à une heure). Elle ne résout pas trois situations :

1. **Carte vide / faible densité** — nouvel arrivant dans une région peu active : rien sur la carte = cul-de-sac.
2. **« Je serais partant si quelqu'un venait »** — le segment qui ne créera jamais une activité publique mais qui *est dans le coin* ce week-end.
3. **Le voyage** — « j'arrive à Chamonix la semaine prochaine, qui est chaud ? » (le cœur du positionnement Junto : rejoindre l'outdoor *où que tu sois*).

**Propriété structurante :** la valeur de la Discovery est **inversement proportionnelle à la densité d'activités**. Elle pique au lancement et dans les zones creuses, et s'efface quand la carte se remplit. Ce n'est pas une baguette « zéro utilisateur » — elle résout le « quelques utilisateurs, activités trop éparses ».

---

## 2. Ce que c'est / ce que ce n'est pas

**C'est** : une **page à part** (jamais la carte), une **liste scrollable de cartes sans photo**, chacune une **« dispo »** (disponibilité). On **clique activement** sur une personne pour lui envoyer une **demande de contact**.

**Ce n'est pas** :
- ❌ Pas sur la carte — 50 personnes dans une ville = 50 pins au même endroit ; des pins de *gens* se lisent comme du dating.
- ❌ Pas de swipe — on scrolle et on clique pour contacter, ce n'est pas « j'aime / j'aime pas ».
- ❌ Pas d'annuaire de profils, pas d'entité « match », pas de DM à froid.

---

## 3. L'objet « dispo »

Quatre champs, **tous logistiques**, **tous requis pour entrer** (voir §5, réciprocité) :

| Champ | Détail | Notes |
|---|---|---|
| **Sport(s)** | 1 à 3 max | >3 = signal dating → refusé. Affiché en pilule `sport · cotation`. |
| **Fenêtre de temps** | bornée, courte, expire seule | Le **début peut être futur** (cas voyage). |
| **Lieu + rayon** | un **lieu choisi** (pas le GPS, via géocodage — voir « Géocoding ») + rayon | Paliers **5 / 10 / 15 / 30 / 50 km + « peu importe »**. Les cartes remontées sont autour de **ce lieu**. |
| **Déplacement** | **5 modes multi-choix** : voiture · moto · vélo · à pied · transports | Aucun plafond de rayon selon le mode (stop / bus / vélo / à pied possibles). |

- **Niveau par sport** : une pilule par sport, avec sa cotation propre (`🧗 Escalade · 5c`, `🎿 Ski rando · autonome`). Montré, mais **jamais un filtre** — jugement humain (cf. §6).
- **Déplacement** : en v1 on **ne modélise pas** le « je viens te chercher ». Les modes sont affichés en pilules ; le covoiturage se règle dans le chat.
- **Une seule dispo active** par utilisateur en v1 (éditable). Les *presets* multiples sont reportés en v2 (§11).

---

## 4. La règle de compatibilité (matching)

**Te sont remontés = même sport ∩ zones qui se recoupent ∩ fenêtres qui se chevauchent.**

- **Sport** : identique.
- **Zone** : les rayons se recoupent — `distance(base_A, base_B) < rayon_A + rayon_B`. Ex. « 70 km autour de Briançon » voit « 10 km autour de Gap ». **Symétrique** par construction (si tu le vois, il te voit → réciprocité).
- **Temps** : simple **chevauchement**, la durée n'importe pas (un « 3 jours » et un « 2 semaines » matchent s'ils se recoupent). Comme les dispos expirent, seules des fenêtres actives existent.

> Note : le rayon est **à vol d'oiseau** — approximation généreuse, pas une promesse de proximité routière (50 km en montagne ≠ 50 km en plaine). Le badge motorisation + le chat gèrent la nuance.

---

## 5. L'expérience d'entrée : recherche à compteur vivant + réciprocité

La « recherche » et la « dispo » sont **le même objet** vu des deux côtés. À mesure qu'on pose ses critères, une **pilule-compteur se met à jour en direct** :

```
Chamonix · 30 km          → « 300 personnes cherchent du sport autour »
+ 🧗 escalade             → « 120 personnes »
+ 14–18 juillet           → « 8 personnes »
```

On *sent* la densité en construisant → on apprend à élargir/rétrécir. C'est l'anti-lurker rendu utile.

**Deux états distincts (clé du modèle) :**
- **Composer** — je règle mes filtres, je vois les **compteurs flous** → je ne suis **pas encore visible**.
- **Activer ma dispo** — ma recherche courante **devient** ma dispo → je deviens **visible** *et* je vois les **cartes**.

La réciprocité tient : les compteurs pendant la compo sont gratuits ; pour accéder aux vraies personnes, je m'expose aussi.

**Garde-fou** : quand le compteur descend très bas (1–2), afficher **« quelques personnes »** plutôt que le chiffre exact — sinon « 1 personne, ce sport, cette micro-zone, ces dates » peut désigner quelqu'un avant toute exposition mutuelle.

---

## 6. Carte vs profil — séparation par fonction

- **La carte Discovery porte la LOGISTIQUE de l'intention** : sport, niveau, fenêtre, distance, déplacement, fiabilité (**avatar + anneau**, pas d'emoji). Tout ce qui décide « *peut-on faire ce truc ensemble ?* ». Pas de photo *dominante* — l'avatar n'apparaît que petit, cerclé, comme signal de fiabilité.
- **Le profil porte l'IDENTITÉ / la confiance** : photo, jugements des pairs, historique de sorties, fiabilité détaillée. Tout ce qui décide « *ai-je envie / confiance ?* ».

→ Carte minimale et rapide à scroller → **tap → profil** pour qui veut creuser. On ne tire pas le profil dans la carte : ça alourdit le scroll et retransforme le parcours en browsing de profils (ce qu'on évite).

---

## 7. Sécurité

Posture assumée (Scott) : **pas d'appareillage lourd**. Réservé aux **18+** (mineurs déjà interdits) + jugement adulte — comme les apps de rencontre outdoor qui fonctionnent malgré des RDV en lieux inconnus.

- **Carte de prévention** au premier contact (« retrouvez-vous d'abord dans un lieu public / au parking du départ », « préviens un proche de ta sortie »).
- **Le funnel vers l'activité est le vrai levier de sécurité** : transformer un 1:1 privé en **sortie postée sur la carte** (point de RDV public, d'autres peuvent voir/rejoindre) est plus sûr — et ça alimente le cœur de l'app (§10).
- Hérité de 00072 : demande → accepter/décliner, décline silencieux, block/report, secteur jamais = domicile ni point exact.

---

## 8. Zéro barrière d'entrée (v1)

Pas de plancher d'activité, pas d'ancienneté de compte, pas de vérification renforcée. Décision Scott (2026-07-28) : lancement **local (commune/région)**, friction minimale voulue au départ ; les abus seront traités *s'ils apparaissent*.

---

## 9. Navigation — où on la place

**Pas de 6ᵉ onglet** dans la navbar (dilue la barre, écrase la carte, et la feature est **épisodique**, pas quotidienne).

- **Entrée permanente dans le menu** (accès délibéré).
- **+ Entrée contextuelle depuis la carte** quand c'est creux autour : bandeau discret *« Rien autour ? 🔎 Vois qui est dispo pour une sortie »*. Ça la fait apparaître **pile au moment du besoin** (carte vide = moment cold-start), sans l'imposer.

---

## 10. Le funnel — Discovery nourrit la carte

```
dispo (page Discovery)  →  demande de contact  →  chat  →  « Proposer une sortie »  →  activité sur la carte
                            [réutilise 00072]                  [CTA léger dans le chat]     [le cœur reste vivant]
```

Une **dispo ≠ une activité** : la dispo dit « **contacte-moi** » (état pré-activité, pas d'événement/places/groupe) ; l'activité dit « **rejoins-moi** ». Cette distinction désamorce à la fois le dating **et** la cannibalisation de la carte. Un **CTA léger** « Proposer une sortie » dans la conversation issue d'une dispo évite que le chat meure en « salut / salut » et ramène l'intention sur la carte.

### Deux actions sur une carte dispo : Contacter + Inviter

Chaque carte porte **deux** actions :

- **Contacter** — envoie une **demande de contact** (flux 00072 : accepter / décliner → chat). L'action par défaut, toujours disponible.
- **Inviter** — invite la personne à **une de tes propres activités**, mais **uniquement si l'activité correspond aux critères de la dispo** :
  - **sport** de l'activité ∈ sports de la dispo,
  - **date/heure** de l'activité ∈ fenêtre de temps de la dispo,
  - **niveau** de l'activité compatible avec le niveau de la dispo (le critère le plus souple — à préciser au build).

  *Exemple :* dispo « escalade · 6a · cette semaine » → invitable à une sortie **escalade, cette semaine, niveau 6a**. Une dispo « canyon · semaine prochaine » **ne peut pas** être invitée à cette sortie escalade. Si aucune de tes activités ne correspond, le bouton **Inviter** est masqué / inactif.

  **Backend :** réutilise `invite_users_to_activity` (00341/00344, déjà durci à l'audit 2026-07-27/28) + un **contrôle serveur de correspondance dispo ↔ activité** (sport ∩ · date ∈ fenêtre · niveau compatible) ajouté avant l'envoi. À valider dans la chaîne d'autorisation.

---

## 11. Périmètre

### v1 (ce qu'on construit)
- Composer/activer une dispo (une seule active, éditable).
- Compteur-filtre vivant (§5) + garde-fou petits nombres.
- Liste de cartes (logistique, sans photo) → tap → profil existant.
- Contact via le système 00072 (`initiated_from = 'discovery'`).
- Action **Inviter** (invite à une activité correspondant aux critères de la dispo — voir §10).
- Carte de prévention sécurité + CTA « Proposer une sortie ».
- Notifications **pull-only** (seules les *demandes reçues* poussent ; pas de « quelqu'un est apparu »).
- Nouveau compte = badge **« nouveau »** neutre (peu de signal, sans pénaliser).
- Nav : menu + entrée contextuelle carte.

### v2 (reporté, conçu pour se greffer sans refonte)
- **Recherches enregistrées / presets** (façon Wyylde) : plusieurs presets (« maison », « voyage »), **seul le preset actif = ta dispo** (une seule active → règle v1 préservée). Sert pile le cas voyage. Purement additif.
- **Messagerie comme hub** : covoiturage, questions, demande privée à un orga, création d'activité après match — cf. mémoire « Messaging + requests UX backlog ». Pour l'instant : simple.
- **Recherche par spot précis** (idée Scott, 2026-07-29) : « je cherche un compagnon pour le **Canyon de Fressinières** » — ancrée sur un **lieu/spot nommé** (pas une ville), **sans date obligatoire**, avec **niveau(x)**. C'est le pendant « intention sur un spot » de la dispo (qui, elle, est « intention sur un secteur + une fenêtre »). Recoupe l'idée « annonce » parkée + les **spots fixes** (mémoire `project_fixed_spots_idea`). Nécessite un **géocodage de toponymes** (IGN Géoplateforme / Photon), donc dépend de ce chantier. Feature distincte du mode dispo — à cadrer à part.

---

## 12. Dos serveur — ~60 % déjà construit

Le **système de demande de connexion (migration 00072**, durci à l'audit 2026-07-27/28) **est** la couche de contact de la Discovery :
- `conversations.status` ∈ (`pending_request`, `active`, `declined`) ; `initiated_from` accepte déjà `'discovery'`.
- `send_contact_request` / `accept` / `decline` / `cancel`, plafond **10 demandes en attente**, cascade de blocage, **décline silencieux**, une demande par paire (pas de renvoi).

**Ce qui reste à construire :** le stockage de la dispo, la requête de matching, le compteur-filtre, l'UI.

---

## 13. Verrous anti-dating (non négociables)

Pas de swipe, pas d'entité match, pas de « c'est un match », pas de bio, pas de genre, tri par **fiabilité** (jamais par photo), décline silencieux. **Vocabulaire** : « partenaires », « demande de contact », « accepter / décliner » — **jamais** « match ».

---

## Design validé — maquettes (2026-07-29)

Design UI/UX arrêté avec Scott dans le langage maison (thème clair crème `#F5EEDF`, vert `#2FA46A`, cartes à liseré, labels capitales). Maquettes de référence (artifacts privés) :
- **Carte dispo (modèle)** : https://claude.ai/code/artifact/0ce9be7e-633e-4d82-8908-75a41ce3df7f
- **Écran Découverte (liste)** : https://claude.ai/code/artifact/4147c772-823c-422e-ba58-63dc75e4e763
- **Composer ma dispo** : https://claude.ai/code/artifact/466996dc-f618-4e4c-957a-b6279e4afac2

### La carte dispo (modèle validé)
- **En-tête** : `Pseudo · à X km` — la **distance de toi** juste après le pseudo (jamais le rayon d'autrui, qui n'est pas affiché) ; **sorties** en sous-ligne, ou badge **« nouveau »** neutre (compte neuf, peu de signal).
- **Fiabilité** = **avatar + anneau** (le ring du profil : vert fiable / ambre intermédiaire / gris nouveau). Vraie photo dans l'app. **Seul élément hors pilule.**
- **Contenu en pilules, sans label** : pilule **sport colorée par son univers** (montagne `#4A7C59` · eau `#2563EB` · air `#8B5CF6` · vélo `#64748B` · à pied `#E11D48`, cf. `src/utils/sport-category-color.ts` — c'est ce qui distingue le multi-sport). Icône **sport** = son icône dédiée (`sport-icons.ts`) ; les **autres pilules** (fenêtre, déplacement) = **icônes en trait** (lucide).
- **3 actions en liens** (style hyperlien souligné, **uniformes**) : **Voir profil · Inviter · Contacter**. Pas de boutons-pavés.

### L'écran Découverte (liste)
- Titre **« Découverte »**, **pas** de bouton réglages en haut.
- **Ta dispo active** en tête : encart vert rappelant tes critères en pilules + liens *Modifier / Désactiver*.
- Séparateur **« N correspondances »**, puis la liste scrollable des cartes.

### L'écran Composer
- **Sport** : réutilise le **SportDropdown existant** (barre qu'on ouvre → recherche + liste des ~36 sports), 1–3, cotation par sport **inline** sur le tag sélectionné.
- **Lieu** : champ **autocomplete géocodé** (voir « Géocoding ») ; **Rayon** : **glissière** (paliers 5/10/15/30/50/∞).
- **Quand** : champ ouvrant un **date picker** natif.
- **Déplacement** : **5 modes** multi-choix (voiture · moto · vélo · à pied · transports), icônes en trait.
- **Compteur épinglé** au-dessus du CTA, **épuré** : juste « **N** personnes correspondent dans ta zone, sur ces critères » (pas de détail 300→120→8). Planché à « quelques » sous 1–2 (cf. §5). CTA **« Activer ma dispo »**.

### Géocoding — champ « Lieu »
**Décision (2026-07-29, cf. DECISIONS.md).** L'app n'utilisait pas de géocodage (on plaçait un pin sur la carte). Pour la Discovery, le lieu se choisit par **autocomplete sur la Base Adresse Nationale** (`api-adresse.data.gouv.fr`, `type=municipality`) : **gratuit, sans clé, sans quota réel, pérenne** (service public Etalab), granularité **commune** — exactement le bon niveau pour un secteur. **France uniquement.** On garde le **pin sur carte** comme alternative/fallback. Les **toponymes naturels** (sommets, cols, spots) ne sont **pas** couverts par la BAN → réservés à **IGN Géoplateforme** ou **Photon/Nominatim** le jour des « spots fixes » (cf. §v2 + la recherche par spot). À l'international : **Photon auto-hébergé** (gratuit, mondial) ou un tier payant.

---

## 14. Esquisse de modèle de données (à valider avant build)

> ⚠️ Per CLAUDE.md : **toute fonction SECURITY DEFINER doit voir sa chaîne d'autorisation présentée à Scott et validée avant d'être codée.** Ce qui suit est une *esquisse de conception*, pas une spec figée.

**Table proposée `discovery_availabilities`** (une ligne active/utilisateur en v1 ; forme prête pour les presets v2) :

| Colonne | Type | Notes |
|---|---|---|
| `id` | UUID PK | |
| `user_id` | UUID FK users, ON DELETE CASCADE | |
| `sport_keys` | TEXT[] | 1–3, chaque clé ∈ `sports.key` |
| `levels` | JSONB | niveau par sport `{ "escalade": "5c" }` |
| `base` | GEOGRAPHY(POINT,4326) | lieu choisi (autocomplete BAN → commune, ou pin carte), pas le GPS |
| `base_label` | TEXT | libellé commune pour l'affichage (« Chamonix-Mont-Blanc ») |
| `radius_km` | INTEGER | ∈ {5,10,15,30,50} ou NULL = « peu importe » |
| `transport_modes` | TEXT[] NOT NULL | ⊂ {`car`,`motorbike`,`bike`,`on_foot`,`public_transport`}, ≥1 |
| `window_start` | TIMESTAMPTZ | ≥ maintenant possible dans le futur |
| `window_end` | TIMESTAMPTZ | CHECK > start, borne max (ex. +4 semaines) |
| `is_active` | BOOLEAN NOT NULL DEFAULT false | index partiel unique `(user_id) WHERE is_active` |
| `created_at` | TIMESTAMPTZ | |

RLS ENABLE + FORCE dès la création ; écritures **uniquement via fonctions SECURITY DEFINER** ; colonnes privilégiées (`user_id`, `is_active`, `created_at`) forcées via trigger whitelist ; gate `(is_demo…)` sans objet ici mais suspension à filtrer.

**Fonctions pressenties (chaînes d'autorisation à définir + valider) :**
- `upsert_dispo(...)` — crée/édite la dispo ; valide sport ≤3, rayon dans l'ensemble, fenêtre bornée, motorisé non-null.
- `activate_dispo(...)` / `deactivate_dispo()` — bascule `is_active` (une seule active).
- `get_discovery_count(filtres)` — compteur flou, **planché** sous un seuil (« quelques »). Ne révèle aucune identité.
- `get_discovery_cards()` — cartes pour la dispo active (exige `is_active` = réciprocité) ; filtre suspension + blocage bidirectionnel ; tri fiabilité.
- Contact : **réutilise** `send_contact_request` avec `initiated_from = 'discovery'`.

---

## 15. Prochaines étapes

1. ~~Construction graphique + templates~~ **FAIT** (2026-07-29) — voir « Design validé — maquettes ».
2. **Décision go / no-go** : la feature est-elle utile ? l'ajoute-t-on ? (discussion à mener — le design est prêt, la décision d'embarquer ne l'est pas encore).
3. Si go : **présenter les chaînes d'autorisation à Scott** (§14) et les valider, **avant** tout code serveur.
4. Puis build v1.
