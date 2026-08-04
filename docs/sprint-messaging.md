# Messagerie — Refonte (spec)

> **Statut : axe actif, design validé en maquettes (2026-08-04), non construit.**
> C'est l'axe B du `docs/PLAN.md`. Refonte **interface ET fonctionnement**.

## Pourquoi
Le chat est aujourd'hui **sous-exposé** : l'onglet Messagerie ne contient que DM + demandes ; les **murs de sortie** (la conversation la plus vivante) vivent uniquement dans le **4ᵉ sous-onglet d'une activité** (`Info · Transport · Matériel · Chat`). Or la communication est **le point fort de Summeet** et un **table-stakes** de toute bonne app. Objectif : **remonter au standard attendu**, pas réinventer le chat — **simple, accessible, vivant** (Summeet = anti-exemple « on s'y perd »).

## Principe : une conversation, deux portes
L'**activité reste une unité auto-suffisante** (Info/Transport/Matériel/Chat) — **inchangée**. La Messagerie devient un **hub** qui **indexe** toutes les conversations et t'y **dépose** (ouvrir une sortie = son onglet Chat). Une seule source de vérité, deux entrées.

## Les pièces

### 1. Le hub (index vivant)
Sorties + groupes + DM **mélangés, triés par récence**, avec **aperçu + non-lus + identité par type** (sortie = carré coloré par univers + icône sport · groupe = pastille · DM = avatar cerclé anneau de fiabilité). **3 types de conversation** : **DM · activité · groupe**. Aperçus rendent le contenu riche (« 🗺️ Trace partagée »).

### 2. Les demandes (inbox d'actions)
**Une seule entrée « Demandes »** en tête du hub, **sectionnée par type** : **Rejoindre une sortie · Covoiturage · Contact · Invitations** (voir pièce 5). Chaque demande **porte un message** :
- **dans la liste** : aperçu du message + accepter/refuser rapides ;
- **au tap** : la **conversation s'ouvre** (carte de contexte + message complet + discuter avant de décider + accepter/refuser).
Modèle unifié : une demande = une **conversation en attente** (déjà vrai pour le contact, 00072). Refus contact **silencieux**.

### 3. Les messages riches (composer « + »)
Dans un fil : **partager une trace GPX** · **partager une sortie** (belle carte tappable : vignette carte + pilule sport + titre + infos) · **créer une sortie** depuis la conversation (pré-remplit les participants du fil). Carte trace GPX = aperçu du tracé + stats (km · D+ · durée) + **profil altimétrique**.

### 4. Les groupes
Créés depuis tes **contacts / partenaires récents** (piocher + nommer). MVP **volontairement simple** (pas de rôles/admin). **Consentement** : on n'ajoute que ses contacts ; chaque membre peut ensuite ajouter les siens → groupe **mixte**, façon WhatsApp ; **blocage = soupape**. But : ton équipe, où l'on **propose des sorties**.

### 5. Les invitations (le miroir des demandes) — **nouveau**
« **X t'invite à rejoindre [sortie]** » (vs « quelqu'un veut rejoindre »). **Accepter = participant** (pas de re-validation — le créateur invite).
- **Émettre** — 2 points d'entrée : (a) **étape 4 de la création** (section « Inviter des partenaires », optionnelle ; sélection = champ du formulaire ; « Publier » crée **et** invite) ; (b) **bouton « Inviter » sur une sortie existante** (+ mot optionnel).
- **Recevoir** — section **« Invitations »** en tête des Demandes.
- **Règles** : le **créateur** invite (un participant peut seulement *partager* la carte) · on invite **uniquement ses contacts** · **pré-approuvé** (accepter = dedans, y compris en mode approbation) · grisé si **complet**.
- **Distinct** de l'existant : **« Partager une sortie »** (carte info, l'autre peut ensuite demander) ≠ **« Inviter à rejoindre »** (officiel). `invite_users_to_activity` (00341/00344) fait aujourd'hui du *partage de carte / demande de contact* — la vraie invitation-à-rejoindre est **à construire**.

**Modèle DB validé (2026-08-04, chaîne d'autorisation approuvée par Scott) :** réutilise **`participations`** avec statut **`invited`** (miroir de `pending`) + colonnes privilégiées `invited_by` / `invite_message` (whitelist trigger). Fonctions SECURITY DEFINER : **`send_activity_invitations(activity, user_ids[], message?)`** (créateur uniquement · contacts/partenaires récents only · cap 20 · skip bloqués/dup/suspendus) · **`accept_activity_invitation(activity)`** (calqué sur 00311 : lock capacité, `invited→accepted`, `junto.activity_full`, **pré-approuvé** = entrée directe) · **`decline_activity_invitation(activity)`** (silencieux). **Pas de réservation** : capacité vérifiée à l'acceptation (comme les demandes) — un `invited` ne compte **pas** dans `participant_count`. Lecture (section « Invitations » des Demandes) : `participations WHERE user_id=me AND status='invited'`, joint activité + inviteur via `public_profiles`.
**Découverte de séquencement :** l'UI d'émission existe déjà (`InvitePartnersSheet`, aujourd'hui branchée sur le card-drop) ; l'UI de **réception** (section « Invitations » des Demandes) appartient à la refonte messagerie **non construite**. → ne PAS repointer l'UI live tant que la réception n'existe pas (sinon invitations créées mais invisibles pour l'invité). Voir § Prochaines étapes.

### 6. Le modèle de données unifié — **[DÉCIDÉ 2026-08-04]**

**Option « données » retenue** (Scott : « le plus propre et le plus sécurisé »). Fenêtre unique : **aucune donnée réelle en prod** (testeurs inactifs, seule la seed démo — régénérable) → migration sans risque, le moment le moins cher de la vie de l'app pour bâtir le modèle durable. **Renverse la décision 2026-04-09 « Deux tables de messages »** (cf. DECISIONS.md 2026-08-04).

**3 tables :**

`conversations` (**étendue**, pas remplacée — le 00072 garde sa colonne vertébrale) :
- `type` : `'dm'` | `'group'` | `'activity'` (CHECK ; `'channel'` réservé v2, accueilli sans être construit)
- `user_1`/`user_2` : **DM only** (CHECK par type), UNIQUE partiel `WHERE type='dm'` — la mécanique paire-unique du gate reste intacte
- `status` : DM = `pending_request/active/declined` (00072 intact) ; group/activity = `'active'` (CHECK)
- `initiated_by/from`, `request_sender_id/message/expires_at` : DM only, **inchangés**
- `activity_id` : activity only, UNIQUE, FK CASCADE — **l'activité possède SA conversation**
- `name` (1–60), `icon` (emoji), `created_by` : group only
- `last_message_at`, `created_at`

`conversation_members` (nouvelle — la couche de lecture uniforme) :
- `(conversation_id, user_id)` PK, FK CASCADE ×2 · `added_by` (audit du consentement) · `joined_at` · **`last_read_at`** (non-lus serveur, remplace le store local du mur)
- Partir = DELETE de la ligne (perte d'accès à l'historique — comportement actuel du mur, assumé pour les groupes)

`messages` (nouvelle — un seul stock, remplace `private_messages` + `wall_messages`) :
- `conversation_id` FK CASCADE · `sender_id` FK **SET NULL** (anonymisation) · `content` 1–2000 · `metadata` JSONB (cartes riches, **toujours construit serveur**) · `edited_at`/`deleted_at`/`created_at` · index `(conversation_id, created_at DESC)` · **`receiver_id` n'existe plus** (la portée = les membres)

**Matrice des règles par type :**

| | **DM** | **Groupe** | **Activité** |
|---|---|---|---|
| Création | **UNIQUEMENT** `send_contact_request` / invite → `pending_request` (invariant 00072 verbatim) | `create_group(name, ids)` — éligibilité ci-dessous, non bloqués, non suspendus | **trigger à la création de l'activité** + membre créateur |
| Membres | 2, figés (lignes créées avec la paire, immuables) | chacun ajoute **ses** éligibles (groupes mixtes, façon WhatsApp) | **asservis aux participations** : `accepted` ⇔ ligne membre (trigger sur `participations`, déjà no-direct-writes → chokepoint unique). ⚠️ Le **créateur n'a PAS de ligne participation** — sa ligne membre vient du trigger de création et la sync ne doit **jamais** la toucher |
| Envoyer | membre + `status='active'` + pas de blocage (2 sens) + rate 15/min (00264) | membre + rate | membre + activité vivante + rate |
| Blocage | envoi coupé ; cascade pending→declined (trigger porté) | messages **restent visibles** (choix WhatsApp assumé) ; bloque l'ajout à de *nouveaux* groupes ; partir = soupape | inchangé (la coordination prime) |
| Lecture (RLS) | ligne membre | ligne membre | ligne membre ≡ RLS actuel du mur (participants acceptés + créateur, 00324) |

**Mécaniques :**
- **Lectures `conversations`** : base **sans lecture directe** (comme elle est déjà sans écriture directe) — vues/RPC curées ; côté émetteur, `declined` **coalescé → pending** (décline silencieux **au niveau DB**, pas seulement en UI).
- **Messages** : RLS direct par appartenance (`EXISTS` ligne membre).
- **Realtime** : **broadcast-trigger curé** (pattern déjà en place pour participations/seat_requests) — pas de `postgres_changes` sur les tables (fuite `status`).
- **Push** : à l'insert message → membres sauf émetteur, `collapseId` par conversation ; fan-out borné par le cap de taille de groupe.
- **Non-lus** : messages `> last_read_at`, sender ≠ moi, non supprimés ; RPC mark-read.
- **Suppression de compte** (par type) : DM = cascade ; groupe/activité = ligne membre cascade + messages anonymisés (`sender SET NULL`). → MAJ « Stratégie de suppression par table » (SECURITY.md) au build.

**Éligibilité inviter / ajouter à un groupe (DÉCIDÉ 2026-08-04)** : **connexions actives ∪ partenaires récents** (une sortie faite ensemble = consentement réel, infalsifiable à bas coût — le cas « groupe post-sortie »).

**Registre des risques (missions de la revue adverse) :**
1. 🔴 **Décline silencieux au niveau DB** — vérifier qu'aucun canal (RLS, vues, realtime, notifs, erreurs de re-send) ne révèle `declined` à l'émetteur ; **vérifier aussi si la fuite existe déjà en prod aujourd'hui** (status lisible via PostgREST ?).
2. 🟠 **Sync membres ⇄ participations** — énumérer TOUTES les transitions de statut (join/rejoin, accept, refuse, withdraw, remove, expire, invited, suppression de compte, démo) ; le membre-créateur hors participations.
3. 🟡 Double représentation DM (paire + membres) — immuable, créée en une transaction, invariant documenté.
4. 🟡 Fan-out push groupes — cap taille (proposition : 20).
5. 🟡 Realtime → bascule complète sur broadcast curé.
6. ⚪ Blocage-dans-groupe visible (assumé) · rename groupe = créateur seul (MVP) · reports sur groupes/messages.

**Paramètres ouverts (non bloquants)** : cap membres groupe (20 ?) · messages système (« X a ajouté Y ») en v1 ? · purge des `declined` à 90 j.

### 7. Extensions (v2, parké)
**Canaux ouverts / par thème** (façon Summeet channels) rattachés au Discovery « gros » — distincts des groupes privés. Messagerie-hub élargie (covoit, questions, demande privée à un orga).

## Contacts = connexions mutuelles (DÉCIDÉ 2026-08-04)

**Plus aucun contact unilatéral.** Scott : « un contact ne se fait pas s'il n'a pas été approuvé ; une fois validé, les deux sont contacts. » Conséquence : le **répertoire one-way (00341)** est **retiré** au moment de la refonte (pas avant — séquencement identique aux invitations). « Mes contacts » ≡ **connexions acceptées du 00072** (send_contact_request → Demandes → accept). La notification « demande en attente » existe déjà (push `contact_request` + section Demandes). Les **partenaires récents** restent une source de *suggestions* (pour envoyer une demande / inviter), pas des contacts. Retrait d'un contact : MVP = le blocage couvre le cas hostile (pas de « déconnexion » douce pour l'instant).

**Éligibilité inviter / ajouter à un groupe** : **connexions ∪ partenaires récents** (une sortie faite ensemble = consentement réel, infalsifiable à bas coût ; c'est le cas d'usage « groupe post-sortie »). **Confirmé par Scott (2026-08-04).**

## Cadrage & invariants
- **Table-stakes, standard-good**, pas maximaliste. Test à chaque écran : *ça ajoute du bruit / on peut se perdre ?* → couper.
- **Consentement / anti-spam** : contacts via demande acceptée ; groupes = contacts only ; blocage = soupape ; refus contact silencieux (00072).
- **Greffe** : toute intégration à un écran existant épouse **le style de cet écran** (ex. l'invite à l'étape 4 suit le récap brutaliste réel, pas mon style rond).

## Maquettes de référence (artifacts privés, 2026-08-04)
- Cartes riches (activité + trace GPX) : https://claude.ai/code/artifact/81a43b3f-bf61-4bb4-a3cb-ee1010ae8394
- Hub + Demandes : https://claude.ai/code/artifact/c470efac-24fd-4838-a0d1-d8cf1895f20e
- Demande + message : https://claude.ai/code/artifact/c4d05b40-5e6d-4c89-81c9-dfcead88dca4
- Créer un groupe : https://claude.ai/code/artifact/db2f5fa7-ab91-4aed-a5dd-0ac955062b6c
- Invitations (3 surfaces) : https://claude.ai/code/artifact/c32e6ee2-922d-4c8b-a798-31e7b504cae7
- Invitation dans la vraie étape 4 : https://claude.ai/code/artifact/ad9b35a7-f39e-4314-afe0-c20add17c3c9

## Prochaines étapes
1. ~~Vérifier les surfaces d'invitation~~ **FAIT** — l'émission existe (`InvitePartnersSheet`, à repointer au build) ; la réception appartient à la refonte ; l'étape-4 création est le seul ajout UI.
2. ~~Trancher le fork~~ **FAIT** — modèle unifié (§6, décidé 2026-08-04).
3. **Revue adverse du DESIGN** (en cours) — missions : fuite decline (n°1), sync participations (n°2), œil neuf global. Synthèse → corrections du modèle si besoin.
4. **Chaînes d'autorisation fonction par fonction** (validation Scott à chaque fois — celle des invitations §5 est déjà validée) : contact-request portées, send_message, create_group/add/leave/rename, triggers (activité, sync, blocage), vues curées, mark-read.
5. **Ordre de build** : une seule vague de migrations (modèle unifié + invitations + contacts-mutuels) + port des fonctions + seed démo régénérée + **audit adverse post-code** (rituel) — puis l'UI (hub → conversation → groupes → invitations → « créer une sortie depuis le chat »).
