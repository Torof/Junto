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

## Lot 1 — Bugs client du parcours (à faire, un commit par point)

### État pending / rejected
- [ ] `menu-sheet.tsx` : « Espace pro » seulement si `status='approved'` (aujourd'hui dès qu'une ligne existe).
- [ ] `pro/espace.tsx` : gérer `isError` de `get_pro_agenda` (assert_approved_pro) ; sous-titre distinct pending / rejected ; tuiles désactivées hors approved.
- [ ] `pro/edit.tsx` : section « Icône du pin » et logo masquées hors approved (les setters exigent approved → erreur générique au tap).
- [ ] `settings-drawer.tsx` : la ligne « En attente » ouvre le formulaire (aujourd'hui dead-end ; seul rejected y mène).
- [ ] `pro/offering/edit.tsx` : garde sur `status`, pas sur l'existence du profil.
- [ ] `pro-detail.tsx` : bannière « page pas encore publique » pour le propriétaire pending ; `use-nearby-pros` ne montre pas son propre pin pending.
- [ ] `pro/edit.tsx` : `company_name`/`real_name` en lecture seule une fois approuvé (B3) + mapping `junto.pro_identity_locked`.

### Notifications
- [ ] `use-push-notifications.ts` : branches `booking_request` → agenda (jour), `booking_declined`/`booking_expired`/`booking_cancelled` (selon `data.by`) → Mes réservations ou agenda. Aujourd'hui demande → page de l'offre, annulation → rien.
- [ ] `notifications-view.tsx` : `booking_request` ouvre le jour / la demande.

### Formulaires et données
- [ ] Champs pro **vidables** : `pro-service.update` envoie `undefined` pour vide + RPC `COALESCE` → impossible de retirer un téléphone / Facebook. Évolution RPC (sentinelle ou `p_clear[]`) + client.
- [ ] Verrou carte 30 j posé **à l'inscription** : ne pas démarrer le compteur avant la 1ʳᵉ modification post-approbation (un refusé doit pouvoir corriger).
- [ ] `offering/edit.tsx` : création non atomique (`create` puis `setDetails`) → doublon au second « Créer ». Un seul RPC ou rollback.
- [ ] Tags matériel / question libre : ajout uniquement sur `onSubmitEditing` → brouillon perdu au blur. Bouton « + » + flush au submit.
- [ ] Minutes de durée non bornées 0-59 ; description requise non trimée ; parse `duration` échoue sur « 1 day 02:00:00 » (écrase à NULL).
- [ ] **KeyboardAvoidingView** dans `pro/edit.tsx` et `offering/edit.tsx` → `useKeyboardDockPadding` ; sheet « Ajouter une réservation » (agenda) sans gestion clavier.
- [ ] `booking-form` : fiche participant envoyée vide = « ✓ Fiche du groupe » trompeur ; texte « Offre indisponible » pour un booking introuvable.

### Cache / rafraîchissement
- [ ] `pro/edit.tsx` submit : invalider `['pro-profile', userId]` et `['pros']` (page publique périmée après édition).
- [ ] Clé `['offering', id]` dans `book/` ≠ `['pro-offering', id]` ailleurs.
- [ ] Pull-to-refresh sur Espace pro, Agenda, Mes réservations, booking-form (aucun refresh ni realtime aujourd'hui).
- [ ] `accept()` renvoie `conversation_id` : invalider `['conversations']`, proposer « Ouvrir la discussion ».
- [ ] Suppression d'offre : `router.back()` retombe sur une page « introuvable ».

### Flux de réservation
- [ ] `book/` : stepper borné aux places **restantes** du créneau choisi ; pré-créneau `?day=&period=` revalidé contre `slots`.
- [ ] `offering-detail` : « Réserver » caché au **propriétaire** (sheet + barre sticky) ; section créneaux vide → dire l'absence de dispos ; `min_participants` affiché mais jamais utilisé (décision).
- [ ] Agenda : « Copier la semaine passée » et listes Demandes / À venir dérivées de la fenêtre chargée (faux négatifs en naviguant loin).

### Photos
- [ ] `pro-detail.tsx` : tuile « Ajouter des photos » du carrousel appelle l'ajout **communautaire** même pour le propriétaire.
- [ ] Flag busy sur les pickers (double tap = deux pickers) ; échec au 3ᵉ fichier non expliqué ; HEIC iOS à vérifier ; ancien logo jamais purgé du storage.

### Conventions
- [ ] Namespace `pro.*` **entier** + ~30 clés `booking.*` + `drawer.becomePro`/`myProPage`, `common.share`/`close`, `calendar.mon…sun`, `proOffering.*` absents de fr.json (textes FR enfermés dans les `defaultValue`).
- [ ] Couleurs/rayons/tailles hors tokens (liste dans l'audit : `espace`, `offering/edit`, `offering-detail`, `pro-offering-card`, `pro-detail`, `availability-calendar`, pins) ; submits pro en `radius.sm` vs booking en `radius.full`.
- [ ] Dead code : `showFullMap` + Modal carte dans `pro-detail`, `equipBlock`, schéma `pro-offering-form` non utilisé ; `Tile` défini dans le render de `espace`.
- [ ] Écrans pro non déclarés dans `app/(auth)/_layout.tsx` (titre de route visible une frame).

---

## Lot 2 — Ergonomie pro (maquette → validation → RN)

- [ ] **Devenir pro** : sortir de Paramètres → Compte (à côté de « Supprimer mon compte ») ; une ligne dans le menu principal, au même emplacement que le futur « Espace pro ».
- [ ] **Inscription** : 13 champs, 5 obligatoires ; « Nom » vs « Nom de la structure » à expliquer (« Nom affiché sur ta page » / « Raison sociale, non publique ») ; lieu en **un geste** (recherche Photon + libellé auto) au lieu de carte plein écran + ville retapée.
- [ ] **Après envoi** : un seul état « En attente » honnête (bannière, « Modifier ma demande », « on te prévient par notification ») ; Espace pro réservé aux approuvés.
- [ ] **Page pro, édition** : deux logiques de sauvegarde (pin au tap, reste au submit) → unifier ou badge « enregistré » ; « Icône du pin / univers » → « Ton pin sur la carte » ; raccourci « Gérer mes photos » ; bouton Enregistrer sticky ou dans le header ; état vide Aperçu « Ajoute ta première sortie ».
- [ ] **Créer une offre** : « Mes offres » ouvre l'onglet Catalogue (ou « + Nouvelle sortie » dans le hub) ; formulaire en **deux temps** (essentiel : sport, titre, 2 lignes, lieu, prix / détails repliés) ; défauts : « Tous niveaux » pré-coché, carte centrée sur l'adresse du pro, nom du lieu pré-rempli ; durée en chips (½ journée, journée, 2h, 3h) cohérentes avec am/pm ; bandeau « Ajoute des photos » tant que la galerie est vide.
- [ ] **Agenda** : demi-journées ≈ 48×26 px → cibles ≥ 44 pt (cellules plus hautes ou vue semaine en édition), libellé matin/après-midi dans la case, jour complet d'un tap ; toggle **optimiste** ; légende « teinte = sport » → « Réservé » ; « Mes dispos » plus visible ; résa manuelle : FAB désactivé sans offre (« Crée d'abord une offre »), chip date avec icône calendrier.
- [ ] **Espace pro** : avatar avec le logo (`pin_image_url`) ; retirer « Bientôt : historique clients & statistiques » ; deux tuiles vers la même page → distinguer ; « n fiches manquantes » → action (ouvrir la conversation).
- [ ] **Vocabulaire unique** : « Demander un créneau » (client), « Demandes » (pro), « Confirmée » partout ; bannir « univers », « teinte = sport », « via l'app / manuel » → « hors app ».

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
