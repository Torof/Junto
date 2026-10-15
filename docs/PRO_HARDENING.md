# Durcissement Pro — checklist vivante

Audit du côté pro (client + base) du 2026-10-08, deux passes parallèles, points lourds recontrôlés à la main. Go de Scott le 2026-10-12 : « on y va ». Ce fichier est la liste de travail des prochains jours — on coche ici, on ne la laisse pas vieillir (règle living-doc).

Objectif (Scott) : un outil pro « très accessible, très joli, très simple, très ergonomique », sans bugs. Pré-lancement : on durcit l'existant, on ne pitche pas de v2.

Lots dans l'ordre validé : **0 sécurité base → 1 bugs client du parcours → 2 ergonomie pro → 3 côté client**. Les lots 2 et 3 passent par maquette → validation → RN.

---

## Lot 0 — Sécurité base (mig 00443) ✅ livré 2026-10-12

- [x] **B1** `pro_profiles_select` : sous-requête `users` no-op → `private.user_is_suspended` + admin non suspendu (pro suspendu visible sur la carte).
- [x] **B2** `cancel_booking` : `client_id != uid` NULL sur une résa manuelle → `IS DISTINCT FROM`.
- [x] **B3** `update_pro_profile` : `company_name`/`real_name` gelés après `approved` → `junto.pro_identity_locked` (i18n FR+EN). Côté client (lot 1) : champs en lecture seule une fois approuvé.
- [x] **B5** Garde `is_demo` côté écriture : `create_pro_review`, `create_offering_review`, `add_pro_community_photo`.
- [x] **B6** `unregister_as_pro` purge `pro_availabilities`.
- [x] **B13** `pro_community_photos` : anon révoqué, policy TO authenticated.
- [x] **D1/D2/D3/D5** SECURITY.md : chaînes des ~20 RPC pro, matrice RLS des 9 tables, colonnes privilégiées, tables RPC-only ; `is_pro_verified` marqué mort ; leçon « policy recopiée » dans « Limitation RLS ».

### Reste en base (mineur, à caler dans un lot ultérieur ou à décider)
- [ ] **B4** Rejouer le REVOKE/GRANT 00418 sans `real_name`/`rejection_reason` — **dépend de ce que la prod embarque** (≥ dbcf2ba ?). Décision Scott.
- [ ] **B8/B14** `status='approved'` dans la policy et la vue des offres (défense en profondeur avant tout chemin « révoquer un pro »).
- [ ] **B9** Cooldown sur `resubmit_pro_application` ; `approve_pro` refuse une cible suspendue.
- [ ] **B10** `approve_pro`/`reject_pro` via `create_notification` (sanitize de `reason`).
- [ ] **B11** Validation de forme `website`/`email`/`phone` côté DB (strip, pas de `javascript:`).
- [ ] **B12** Cooldown enseigne 30 j → `junto.pro_location_cooldown` + i18n (aujourd'hui erreur générique).
- [ ] **B15** Storage `pro-photos` : pas de cap d'objets, pas de purge des orphelins.
- [ ] **B16** `private.pro_photo_url_ok` : hôte du projet codé en dur → `app_config`.
- [ ] **B17** Documenter les trous assumés de la machine à états booking (pas d'unicité inter-offres, capacité informative).
- [ ] **B6 bis (décision)** CASCADE à la désinscription / suppression d'offre efface les réservations PASSÉES des clients et les avis → soft-delete ?
- [ ] **B18 (décision)** Avis gated sur réservation effectuée, maintenant qu'une preuve existe (`bookings.accepted` + date passée) ? Et aucun `reports.target_type` ne couvre une page pro / une offre elle-même.

---

## Lot 1 — Bugs client du parcours ✅ livré 2026-10-12 (mig 00444 + OTA preview)

### État pending / rejected
- [x] `menu-sheet.tsx` : « Espace pro » seulement si `status='approved'`.
- [x] `pro/espace.tsx` : agenda désactivé hors approved ; état unique pending / rejected (titre, texte, bouton « Modifier / Corriger ma demande ») à la place du dashboard.
- [x] `pro/edit.tsx` : section « Icône du pin » et logo réservées à approved.
- [x] `settings-drawer.tsx` : la ligne « En attente » ouvre le formulaire.
- [x] `pro/offering/edit.tsx` : garde sur `status='approved'`.
- [x] Pin pending jamais affiché : `proService.getNearby` filtre `status='approved'` (la RLS montre sa propre ligne). Bannière « page pas encore publique » sur `pro-detail` → inutile, l'Espace pro porte l'état.
- [x] `pro/edit.tsx` : identité éditable jusqu'à approbation (pending **et** rejected), masquée ensuite (gel serveur 00443).

### Notifications
- [x] `use-push-notifications.ts` : branches `booking_request` / `booking_accepted` / `booking_declined` / `booking_expired` / `booking_cancelled` (selon `data.by`), miroir de la vue in-app.
- [ ] `notifications-view.tsx` : `booking_request` ouvre le **jour** / la demande → avec le chantier calendrier (lot 2).

### Formulaires et données
- [x] Champs pro **vidables** : `update_pro_profile(... p_clear TEXT[])` (00444, liste blanche 7 colonnes) ; le client nomme les champs vidés.
- [x] Verrou carte 30 j : seulement une fois **approuvé** (00444) ; `junto.pro_location_cooldown` à la place du générique ; le client suit.
- [x] `offering/edit.tsx` : si `set_offering_details` échoue après create/update, on atterrit quand même sur l'offre avec un toast explicite (plus de doublon au second « Créer »).
- [x] Tags matériel / question libre : commit au blur + flush au submit (le « + » visible = lot 2 avec le formulaire en deux temps).
- [x] Minutes 0-59 validées ; description trimée ; parse `duration` gère « N day(s) HH:MM:SS ».
- [x] Sheet « Ajouter une réservation » (agenda) : `useKeyboardDockPadding` + `Animated.View`.
- [~] **KeyboardAvoidingView** dans `pro/edit.tsx` et `offering/edit.tsx` : **conservé**. Règle maison exacte (mémoire 2026-06-10) : KAV banni des chat docks et bottom sheets ; `behavior` iOS padding / Android undefined est le pattern accepté pour les **formulaires ScrollView** (UX_UI.md:275). Pas de bug remonté sur ces deux écrans.
- [x] `booking-form` / `my-bookings` : le ✓ compte les fiches réellement remplies ; « Réservation introuvable » pour un booking absent.

### Cache / rafraîchissement
- [x] `pro/edit.tsx` submit : invalide `['pro-profile', userId]` + `['pros']`.
- [x] `book/` : clé `['pro-offering', id]` alignée ; invalide `['pro-availability', pro_id]` après envoi.
- [x] Pull-to-refresh sur Espace pro, Agenda, Mes réservations.
- [ ] `accept()` renvoie `conversation_id` : proposer « Ouvrir la discussion » → lot 2 (fiche demande).
- [x] Suppression d'offre : `router.dismissTo(page pro)` au lieu de retomber sur « introuvable ».

### Flux de réservation
- [x] `book/` : stepper borné aux places **restantes** du créneau choisi ; pré-créneau revalidé à l'arrivée des dispos (toast + désélection).
- [x] `offering-detail` : « Réserver » et créneaux cachés au **propriétaire** ; 0 créneau → « Pas encore de créneau ouvert — reviens bientôt » sans bouton.
- [ ] `min_participants` affiché mais jamais utilisé → décision Scott.
- [ ] Agenda : « Copier la semaine passée » et listes dérivées de la fenêtre chargée → avec le chantier calendrier (lot 2).

### Photos
- [x] `pro-detail.tsx` : tuile « Ajouter des photos » → galerie pour le propriétaire, communautaire pour les autres.
- [ ] Flag busy sur les pickers ; échec partiel non expliqué ; HEIC iOS ; ancien logo non purgé → lot 2 (photos).

### Conventions
- [x] fr.json + en.json : namespace `pro.*` complet, clés `booking.*` du hub/agenda/manuel, `drawer.becomePro`/`myProPage`, `common.share/close/delete/save`, `calendar.mon…sun`, `proOffering.*` (validations). Les `defaultValue` restent dans le code comme filet.
- [ ] Couleurs/rayons/tailles hors tokens (liste dans l'audit : `espace`, `offering/edit`, `offering-detail`, `pro-offering-card`, `pro-detail`, `availability-calendar`, pins) ; submits pro en `radius.sm` vs booking en `radius.full`.
- [ ] Dead code : `showFullMap` + Modal carte dans `pro-detail`, `equipBlock`, schéma `pro-offering-form` non utilisé ; `Tile` défini dans le render de `espace`.
- [ ] Écrans pro non déclarés dans `app/(auth)/_layout.tsx` (titre de route visible une frame).

---

## Lot 2 — Ergonomie pro ✅ livré 2026-10-15 (maquette validée le jour même, 5 commits f74f3c7→i18n, OTA preview)

- [x] **Devenir pro** dans le Menu, à la place qu'occupe ensuite « Espace pro » (statut pending/rejected au même endroit) ; retiré de Paramètres › Compte.
- [x] **Inscription** : quatre champs (« Nom affiché sur ta page », « Raison sociale · non publique », « Ton nom et prénom · non public », « Où te trouver ») ; lieu en un geste (PlaceSearchBar Photon → ville + pin, mini-carte pour ajuster) ; Contact et Slogan/description repliés, optionnels ; CTA sticky « Envoyer ma demande » + note.
- [x] **Après envoi** : fait au lot 1 (Espace pro réservé aux approuvés, état unique).
- [x] **Page pro, édition** : une seule logique de sauvegarde (pin + logo appliqués avec Enregistrer, upload du logo au choix) ; « Ton pin sur la carte » ; Adresse / Contact repliés avec résumé ; ligne « Photos de la page » → onglet Photos ; CTA sticky ; note identité vérifiée. **Reste** : état vide Aperçu « Ajoute ta première sortie ».
- [x] **Créer une sortie** : « + Nouvelle sortie » dans le hub ; « Mes sorties » ouvre l'onglet Catalogue (`?tab=catalog`) ; formulaire en deux temps (essentiel / détails repliés avec valeur courante) ; défauts « Tous niveaux », lieu = adresse du pro ; durée en chips ; « + » sur les tags. **Reste** : bandeau « Ajoute des photos » tant que la galerie est vide.
- [x] **Agenda** : cellules 108 pt, demi-journées ≥ 42 pt libellées matin / a-midi ; segmenté Consulter / Modifier mes dispos ; toggle optimiste ; légende « Réservé » ; raccourcis derrière un bouton (feuille) ; « + Résa » en en-tête à la place du bouton flottant. **Reste** : FAB désactivé sans offre, icône calendrier sur le chip date, listes dérivées de la fenêtre chargée.
- [x] **Espace pro** : logo du pin, « Bientôt » retiré, quatre tuiles distinctes. **Reste** : « n fiches manquantes » → action.
- [~] **Vocabulaire unique** : « Réservé », « matin / a-midi », « Modifier mes dispos » posés ; « Demander un créneau » côté client = lot 3.

---

## Lot 3 — Côté client

- [ ] **Fiche offre** : prix affiché deux fois (header + barre sticky) ; « Contacter » ouvre la page du pro → « Voir sa page » ou un vrai contact ; créneaux vides en sheet ; « dès N pers. » non répercuté.
- [ ] **Réserver** : « Réserver » sur l'offre puis « Envoyer la demande » → « Demander un créneau » dès l'offre (le pro confirme).
- [ ] **Mes réservations** : dire la suite après envoi (« le pro répond en général sous 24 h ; sans réponse la demande expire le jour même ») ; annulation jour J d'une résa confirmée : rappeler de prévenir aussi par message.
- [ ] **Carte** : 2ᵉ tap sur une offre dans la liste basse pousse la page plein écran alors que le pin ouvre le drawer → unifier sur le drawer.

---

## Décisions ouvertes (Scott)

1. **Vérification SIRET / diplôme** : PRODUCT.md la promet, le formulaire ne demande rien et l'admin n'a rien à vérifier. Retirer la promesse ou ajouter un champ SIRET ?
2. **Avis gated** sur une réservation effectuée (preuve disponible depuis 00416) ?
3. **`real_name` REVOKE** : rejouer dès que la prod embarque ≥ dbcf2ba — vérifier l'état réel de la prod d'abord.
4. **`min_participants`** : l'utiliser dans le flux (avertir sous le minimum) ou le retirer de l'affichage ?
5. **Soft-delete** des offres / profils pour préserver l'historique client et les avis ?
6. **Docs** : PRODUCT.md §Pro dit encore « pas de booking » (modèle 2026-06-10) — réécrire sur DECISIONS 2026-09-17 ; UX_UI.md:275 documente encore un pattern KeyboardAvoidingView contraire à la règle maison.
