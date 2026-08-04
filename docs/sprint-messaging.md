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
**Fil pré-acceptation (arbitrage 2026-08-04)** : possible **seulement** sur rejoindre / covoit / invitation (refus non silencieux là), **ouvert par le destinataire** — l'émetteur ne peut jamais écrire au-delà du message porté par sa demande. Demandes de **contact** : 1 message, pas de fil avant acceptation.

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
| Membres | 2, figés (lignes créées avec la paire, immuables) | chacun ajoute **ses** éligibles (groupes mixtes, façon WhatsApp) | **asservis aux participations** : `accepted` ⇔ ligne membre, **créateur compris** (`create_activity` insère sa ligne `accepted` — 00316:179 ; c'est déjà comme ça qu'il lit le mur, RLS 00324 n'a aucune clause créateur). **Aucun cas spécial** : le trigger de création ne crée QUE la conversation ; toutes les lignes membres viennent de la sync (trigger sur `participations`, no-direct-writes → chokepoint unique) |
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

**Éligibilité inviter / ajouter à un groupe (DÉCIDÉ 2026-08-04, durci post-revue)** : **connexions actives ∪ partenaires récents durcis** — partenaire récent = **ma présence validée** sur une sortie commune non annulée/expirée, fenêtre 180 j (l'ancienne définition se fabriquait en un simple join public). Pour l'**ajout à un groupe**, condition supplémentaire : **aucune conversation non-active** entre la paire (un décliné/pending ne peut pas être contourné par un « groupe de 2 » = DM sans gate).

### Durcissements issus de la revue adverse du design (2026-08-04 — 3 relecteurs, tout intégré)

**Fait immédiatement (migration `00350`, appliquée en prod)** : `decline_contact_request` interdit à l'émetteur (oracle) · plafond des 10 compté **émetteur seul** · compteurs **decline-blind** (un `declined` occupe son slot jusqu'à `created_at + 30 j`, comme un pending intouché — idem compteur invite) · `join_activity` gate `is_demo`.
**Reste vivant, assumé jusqu'au rebuild** : la policy SELECT de `conversations` expose `status` à l'émetteur (PostgREST). **Première brique du build** = lectures curées (aucun utilisateur réel actif ; risque documenté).

**Sync membres ⇄ participations** : trigger row-level `AFTER INSERT OR UPDATE OR DELETE`, `WHEN (OLD.status IS DISTINCT FROM NEW.status)` sur UPDATE ; règle de gain (`→accepted` ⇒ INSERT membre `ON CONFLICT DO NOTHING`) et de perte (`accepted→autre` ⇒ DELETE tolérant) — **symétrique** car re-join = UPDATE et retrait = UPDATE ; pur trigger de données (jamais `auth.uid()`, tolérant aux cascades — suppression de compte, reset démo — sinon ces flux avortent) ; **non DEFERRABLE** ; RAISE si `user_id`/`activity_id` re-pointés ; script de **réconciliation/backfill** (sert aussi au backfill initial des activités existantes). L'inventaire des **23 transitions** vérifiées est dans le rapport de revue (mission sync).

**Invitations — intégration au cycle réel** : `invited` **expire** (étendre le trigger 00263 à `('pending','invited')` + filtrer la lecture sur activité vivante) · `join_activity` reçoit une **branche `invited`** (sinon il dégrade l'invitation en demande) · la **cascade de blocage** nettoie aussi les `invited` · le refus d'invitation n'écrit **pas** `refused_at` (sinon cooldown 24 h infligé) — statut terminal propre ; ré-inviter un `withdrawn/refused/expired` = UPDATE `terminal→invited` · `send_activity_invitations` : éligibilité **côté serveur**, cap **par 24 h** (pas seulement par appel), `RETURNS VOID` (aucun décompte observable), message + titre strippés.

**Groupes — anti-abus** : éligibilité durcie (ci-dessous) · blocage vérifié addee ↔ **chaque membre** (refus de l'ajout) · **notification à l'ajout** (jamais de membre silencieux) · rate limits `create_group` ~5/j + ajouts ~30/j · cap **20 membres** · `name` strip-HTML + 1–60, `icon` CHECK court · groupe **reportable** (nouveaux targets de report : `message` unifié + `group`) · pushes **supprimés** vers les membres ayant bloqué l'émetteur (le message reste visible) · groupe vide (dernier départ) ⇒ suppression de la conversation.

**Schéma — compléments obligatoires** : `reply_to_message_id UUID REFERENCES messages ON DELETE SET NULL` (**les réponses en fil existent depuis 00208 — ne pas les perdre**) + validation même-conversation · trigger **strip-HTML** sur `messages` (pattern 00006) · index `sender_id` · `created_by`/`added_by` **nullable + ON DELETE SET NULL** (sinon la suppression de compte casse sur FK ; rename impossible si `created_by IS NULL`) · `conversation_members.hidden_at` (**porte `hide_conversation`**, dé-masquage au message entrant — généralise aux 3 types) · CHECKs par type complets **dont `user_1 < user_2`** (l'ordre n'est garanti que par les fonctions aujourd'hui) · bornes numériques lon/lat/ele sur le GeoJSON des traces partagées.

**Lectures & temps réel** : helper `private.is_conversation_member(uuid,uuid)` SECURITY DEFINER (sans lui, couper la lecture de `conversations` casse les policies de `messages` — piège RLS réel) · les vues émetteur **ne font jamais disparaître une ligne** (bloqué/décliné/expiré rendus identiques à pending) et **calculent** `request_expires_at = created_at + 30 j` au lieu d'exposer la colonne · jamais `status` exposé · badge du hub via topic broadcast **par utilisateur** (ou polling) — plus de `postgres_changes` sur les tables.

**Push & limites** : `send-push` étendu à `user_ids[]` → **1 seul** `http_post` par message (fan-out dans l'edge function, Expo batch 100) · rate limits : DM 15/min · groupe & activité 30/min (parité mur) · **cap global émetteur 60/min** toutes conversations · nom de groupe **sanitized** avant tout push (UGC en territoire notification).

**Doctrine & dette doc à porter dans la vague** : colonnes privilégiées par table (whitelist triggers, `last_read_at` = seul champ client-atteignable, via RPC monotone) · codes `junto.*` + i18n FR/EN pour tous les nouveaux cas (y compris le rate-limit de `share_activity_message` resté générique) · MAJ CLAUDE.md (liste no-direct-writes : `conversations`/`conversation_members`/`messages`), SECURITY.md (matrice RLS, stratégie de suppression, rate limits, realtime/push, classification des fonctions), régénération des types TS, seed du read-state local (sinon tout apparaît non-lu au premier lancement post-refonte) · l'**inventaire complet des objets de la vague** (tables/policies/triggers/16 fonctions/realtime/client) est dans le rapport de revue (mission holistique).

### Arbitrages Scott (2026-08-04 — tous validés)
1. **Fil pré-acceptation** : uniquement sur **rejoindre / covoit / invitation** (où le refus n'est pas silencieux), et c'est **le destinataire qui ouvre** le fil (l'émetteur n'a que son message porté par la demande). Les **demandes de contact** : 1 message, pas de fil, décline silencieux intact.
2. **Partenaire récent (durci)** = **ma présence validée** sur la sortie (geo/QR/pairs) + activité non annulée/expirée + fenêtre 180 j. (L'ancienne définition se fabriquait en un join public.)
3. **Rétention hub** : conversations d'activités terminées visibles **~30 j** après la fin, puis masquées du hub (historique toujours lisible via l'activité) ; les `deleted_at` (modération) jamais montrées.
4. **`hide_conversation`** : porté en `hidden_at` par membre.
5. **Accusés de lecture : non** — chacun ne voit que son propre `last_read_at` (RLS membres = own rows ; jamais d'état de lecture d'autrui, surtout pas sur un DM pending).

**Paramètres restants (à fixer au build, non bloquants)** : messages système (« X a ajouté Y ») en v1 ? · purge des `declined` à 90 j.

### 7. Extensions (v2, parké)
**Canaux ouverts / par thème** (façon Summeet channels) rattachés au Discovery « gros » — distincts des groupes privés. Messagerie-hub élargie (covoit, questions, demande privée à un orga).

## Contacts = connexions mutuelles (DÉCIDÉ 2026-08-04)

**Plus aucun contact unilatéral.** Scott : « un contact ne se fait pas s'il n'a pas été approuvé ; une fois validé, les deux sont contacts. » Conséquence : le **répertoire one-way (00341)** est **retiré** au moment de la refonte (pas avant — séquencement identique aux invitations). « Mes contacts » ≡ **connexions acceptées du 00072** (send_contact_request → Demandes → accept). La notification « demande en attente » existe déjà (push `contact_request` + section Demandes). Les **partenaires récents** restent une source de *suggestions* (pour envoyer une demande / inviter), pas des contacts. Retrait d'un contact : MVP = le blocage couvre le cas hostile (pas de « déconnexion » douce pour l'instant).

**Éligibilité inviter / ajouter à un groupe** : **connexions ∪ partenaires récents durcis** — définition canonique en §6 (présence validée + activité vivante + garde anti-« groupe de 2 »). **Confirmé par Scott (2026-08-04).**

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

## Chaînes d'autorisation — TOUTES VALIDÉES (Scott, 2026-08-05, lots ①→⑤)

23 chaînes approuvées en 5 lots (le détail complet vit dans la conversation de validation ; chaque fonction sera consignée dans SECURITY.md « Chaîne d'autorisation complète par fonction » au moment de son code, convention maison) :
- **① Socle DM & envoi** : `send_contact_request` (port 00350 + type='dm' + 2 lignes membres) · `accept_contact_request` (destinataire seul, 1er message dans `messages`) · `decline_contact_request` (status-blind, no-op sur déjà-declined) · `send_message` (unifiée, gates par type, metadata jamais client, rate limits dm 15/groupe·activité 30/global 60 par min, push batch, unhide) · `edit/delete_message` (parité 00044/00177) · `mark_conversation_read` (monotone, no-op non-membre) · `set_conversation_hidden` · **+ `reply_to_request`** (le destinataire d'une demande rejoindre/covoit/invitation ouvre le fil → crée-ou-active le DM ; amende l'invariant 00072 en « jamais de DM actif sans consentement des deux » — demande = consentement de l'émetteur, réponse = celui du destinataire ; les demandes de contact restent hors mécanisme).
- **② Groupes** : `create_group` (5/24 h, cap 20, skips silencieux à causes fusionnées, éligibilité + garde anti-groupe-de-2, blocage vs chaque retenu, notif à chaque ajouté) · `add_group_member` (tout membre ajoute, 30/24 h, blocage vs chaque membre, notif) · `leave_group` (dernier parti ⇒ conversation supprimée) · `rename_group` (créateur-et-membre seul, strip à l'écriture).
- **③ Triggers** : création conversation d'activité (`ON CONFLICT DO NOTHING`, zéro ligne membre) · sync participations⇄membres (row-level, `WHEN status change`, gain/perte symétriques, tolérant cascades, non-DEFERRABLE, RAISE sur re-pointage) + script réconciliation/backfill · cascade blocage étendue (DELETE des `invited` de la paire) · expiry 00263 étendue (`pending`+`invited`).
- **④ Invitations** : `send_activity_invitations` (créateur seul, VOID, cap 20/appel + 30/24 h, éligibilité serveur, terminal→invited en UPDATE, strip) · `accept_activity_invitation` (capacité à l'acceptation, la sync fournit membre+chat) · `decline_activity_invitation` (DELETE silencieux, jamais `refused_at`) · `join_activity` branche `invited` (→ accepted, pré-approuvé).
- **⑤ Lecture & diffusion** : `conversations` sans lecture directe ; `messages` RLS par appartenance + filtres auteur par type ; membres own-rows-only · `get_conversations` (rétention 30 j, demo par appartenance) · `get_conversation_state_with` (**coalescence declined→pending_sent**, couvre aussi le blocage-cascade, la ligne ne disparaît jamais) · RPC Demandes par source (expiration calculée) · realtime broadcast curé (topics `conversation:<id>` + `user:<id>`, retrait des publications) · `send-push` batch `user_ids[]` · enveloppes de partage (share-gates + `junto.share_rate_limit` + bornes GeoJSON) · « créer une sortie depuis le chat » = composition de briques existantes, zéro fonction nouvelle.

## Ordre de build
- **Brique 1 — fermer la fuite `status`** (schéma actuel, survit à la vague) : RPC `get_conversation_state_with` + lectures messagerie minimales → **repointage client + OTA d'abord**, **puis** DROP `conversations_select_own` + REVOKE en migration séparée (sinon les apps testeurs en lecture directe cassent — deux temps obligatoires).
- **Brique 2 — la vague** (session dédiée) : DDL complet (extension conversations, members, messages, CHECKs, FK, triggers ③, helper, whitelist, index) + port des fonctions ①②④⑤ + realtime + send-push batch + backfill + drop des vieilles tables + seed démo régénérée + types TS.
- **Brique 3 — audit adverse post-code** (rituel).
- **Brique 4 — UI** : hub → conversation (cartes riches) → groupes → invitations (étape 4 création + repoint `InvitePartnersSheet`) → « créer une sortie depuis le chat » ; OTA preview, tests Scott.
- **Brique 5 — bascule contacts-mutuels** : retrait du roster 00341, écran Contacts = connexions.
