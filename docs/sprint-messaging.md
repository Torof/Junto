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

### 6. Le fonctionnement — **[DÉCISION OUVERTE, structurante]**
Aujourd'hui 3 objets : `wall_messages` (murs) · `private_messages` (DM) · `conversations` (demandes). Fork :
- **Présentation** : l'inbox **agrège** les 3 sources (moins risqué, plus rapide).
- **Données** : un **modèle de conversation unifié** dessous (plus propre, plus lourd, touche 00072).
C'est ce qui décide si c'est un gros ou un très gros chantier.

### 7. Extensions (v2, parké)
**Canaux ouverts / par thème** (façon Summeet channels) rattachés au Discovery « gros » — distincts des groupes privés. Messagerie-hub élargie (covoit, questions, demande privée à un orga).

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
1. **Vérifier les 2 surfaces d'invitation restantes** contre leurs écrans réels : bouton « Inviter » sur une sortie existante (confronter à `src/components/activity-detail.tsx`) ; l'invitation reçue (Demandes, écran neuf).
2. **Assembler « créer une sortie depuis le chat »** (créer + inviter les gens du fil — débloqué par la pièce 5).
3. **Trancher le fork présentation vs données** (pièce 6) → cadre l'ampleur.
4. Puis, avant tout code DB : **chaînes d'autorisation** présentées et validées (per `CLAUDE.md`).
