# Junto — Backlog

## Approche
Développement agile par sprints. Chaque sprint livre quelque chose de fonctionnel et testable. On valide avant de passer au sprint suivant.

---

## Sprint 1 — Foundation & Auth
**Objectif :** L'app démarre, l'utilisateur peut s'inscrire et voir la carte avec des activités de test. Toute l'architecture, la sécurité et le tooling sont en place.

### Phase A — Project Foundation
- [ ] Setup Expo + TypeScript + Expo Router
- [ ] Comprehensive .gitignore
- [ ] ESLint + Prettier configuration
- [ ] Path aliases (`@/...`)
- [ ] .env + .env.example (Supabase, Mapbox, Google Places keys)
- [ ] Design tokens (colors, spacing, radius, typography, fonts loading)
- [ ] i18n setup (react-native-i18next, FR + EN, base translation files)
- [ ] Custom dev build (EAS, requis pour Mapbox)

### Phase B — CI/CD
- [ ] GitHub repo + GitHub Actions (lint + typecheck on push)
- [ ] EAS Build profiles (development, preview, production)
- [ ] EAS Update configuration (OTA)
- [ ] npm audit in CI pipeline

### Phase C — Backend Foundation
- [ ] Supabase project creation (remote — no local Docker setup for MVP) + PostGIS activation
- [ ] Supabase security config (disable GraphQL, session duration 1h/30d, rate limiting, DB connection restrictions, email change protection, uniform auth error messages — prevent account enumeration, OAuth redirect URI lockdown, email confirmation ENABLED, password minimum 8 chars, statement timeout configuré)
- [ ] All 8 tables with migrations and constraints : users, activities, sports, participations, wall_messages, private_messages, notifications, blocked_users (text fields: strip HTML tags via DB trigger). Contraintes clés : UNIQUE(user_id, activity_id) sur participations, display_name CHECK(2-30) + bio CHECK(<=500), title CHECK(3-100) + description CHECK(<=2000), message content CHECK(1-2000), sport_id ON DELETE RESTRICT, push_token privileged, creator_id + status immutables via trigger (avec bypass par session variable pour fonctions autorisées), invite_token UUID
- [ ] Trigger `on_auth_user_created` — crée la ligne public.users automatiquement (pas d'INSERT client sur users). No INSERT RLS policy for clients on users table.
- [ ] Trigger unique `handle_user_update` — approche whitelist : force les colonnes privilégiées à OLD, n'autorise que display_name/avatar_url/bio/sports/levels_per_sport, auto-update updated_at. Bypass via session variable. Un seul trigger par table (fusionne column lock + updated_at).
- [ ] Trigger unique `handle_activity_update` — même approche whitelist : creator_id/status/invite_token/created_at forcés à OLD, champs conditionnellement verrouillés quand participants existent, auto-update updated_at.
- [ ] Contrainte CHECK duration >= 15 minutes sur activities
- [ ] Vue `public_profiles` — expose uniquement les colonnes publiques (display_name, avatar_url, bio, sports, levels_per_sport, created_at). GRANT SELECT to anon + authenticated. Pas de GRANT SELECT sur table users pour anon. Toutes les queries publiques passent par la vue.
- [ ] Sports reference data in migration (climbing, hiking, kayaking, skiing, cycling, etc. — not seed data, required for app to function)
- [ ] RLS policies on every table (including suspended_at + blocked_users filters, column-level restrictions on privileged fields, DELETE policy on blocked_users: only blocker can unblock, sports: admin-only write, activities: no DELETE policy, suspended_at filter on discovery only not history, NO INSERT policy for clients on: users, notifications, wall_messages, private_messages — inserts via SECURITY DEFINER functions only — see SECURITY.md)
- [ ] REVOKE EXECUTE sur fonctions internes (create_notification, transition_activity_status, tous les triggers, generate_random_name) pour anon ET authenticated. REVOKE EXECUTE from anon sur toutes les fonctions client-callable. SET search_path = public sur toutes les fonctions SECURITY DEFINER.
- [ ] Storage buckets + policies (avatars public — path fixe `/avatars/{user_id}/avatar` pour overwrite, pro-documents private — Sprint 6. Pas de bucket GPX — GPX parsé côté client, coordonnées stockées en PostGIS)
- [ ] Auto-generated TypeScript types
- [ ] Seed data script (`supabase/seed.sql` — test activities, test users, production guard: script must not run against prod)

### Phase D — App Architecture
- [ ] Supabase client setup with expo-secure-store + TanStack Query provider
- [ ] Service layer structure (authService, activityService, userService)
- [ ] Network awareness (TanStack Query onlineManager + NetInfo)
- [ ] Expo Router navigation structure with auth/visitor split (unauthenticated: map visible without account — valeur immédiate; authenticated: full 4 tabs — Carte, Mes activités, Messagerie, Profil with placeholders)

### Phase E — Core Features
- [ ] Auth flow : Google + Email (Supabase Auth — includes Google Cloud Console OAuth setup with dev build SHA-1)
- [ ] Registration with random generated name
- [ ] Date of birth + age verification (18+, UX légère — simple date picker)
- [ ] ToS + Privacy Policy consent tracking (mechanism only — consent timestamps recorded, actual legal text is Sprint 8)
- [ ] Country detection via IP at first launch (lightweight free IP geolocation service)
- [ ] Mapbox Outdoors base map (vérifier et désactiver la télémétrie Mapbox SDK ou documenter pour la privacy policy Sprint 8)
- [ ] Display seed activities as pins on map (includes first PostGIS query via activityService.getNearby + useNearbyActivities hook, no pin interaction yet)

**Livrable :** App qui démarre, carte visible avec pins de test, connexion/inscription fonctionnelle. Architecture, sécurité et tooling complets — prêts pour Sprint 2+.

---

## Sprint 2 — Découverte des activités
**Objectif :** Un visiteur peut explorer les activités autour de lui.

- [ ] Pins interactifs sur la carte (niveau 1 — icône sport, titre, heure, places)
- [ ] Pop-up rapide au tap sur un pin (niveau 2)
- [ ] Page événement complète en lecture seule (niveau 3 — bouton "Rejoindre" visible mais redirige vers auth uniquement, mécanique de join en Sprint 4)
- [ ] Vue liste des activités (style Leboncoin)
- [ ] Géolocalisation avec permission + fallback recherche par ville (Google Places)
- [ ] Clustering des pins sur zones denses
- [ ] Distinction visuelle en cours / bientôt / à venir (en cours : starts_at passé et activité non terminée, bientôt : starts_at dans les 2 prochaines heures, à venir : au-delà)
- [ ] Filtres de base (sport, date, distance)

**Livrable :** Exploration complète de la carte et de la liste, sans compte.

---

## Sprint 3 — Création d'une activité
**Objectif :** Un utilisateur connecté peut créer et publier une activité.

- [ ] Bouton "+" flottant sur la carte (auth-aware : visiteur → redirect auth, connecté première fois → vérification téléphone, connecté vérifié → flow création)
- [ ] Vérification numéro de téléphone (première création — nécessite SMS provider type Twilio, configuré dans Supabase Auth)
- [ ] Flow création en 4 étapes (React Hook Form + Zod)
  - Étape 1 : Sport (depuis table sports avec icônes) + titre + description + niveau + places
  - Étape 2 : Point de départ (pin carte) + point RDV (pin carte) + tracé itinéraire + date/heure/durée (day.js)
  - Étape 3 : Mode de visibilité (4 modes — les 2 modes privés visibles mais désactivés avec label "Premium", gate fonctionnelle en Sprint 6)
  - Étape 4 : Récap + publication
- [ ] Import GPX (optionnel, avec validation XML sécurisée)
- [ ] Fonction Postgres de création d'activité (vérifie phone_verified = true, rate limiting : 4/mois free, 2/jour tous tiers, tier check pour visibility private_link, auto-insert créateur comme participant accepté — voir SECURITY.md "Chaîne d'autorisation")
- [ ] Transitions automatiques de statut des activités (pg_cron ou Edge Function : published → in_progress quand starts_at atteint, in_progress → completed quand starts_at + duration atteint → déclenche notification review, published → expired quand starts_at + 2h passé sans participants)
- [ ] Verrouillage des champs critiques après premier participant (hors créateur — Postgres trigger côté DB, pas service layer : bloque UPDATE sur lieu/date/niveau/places/visibilité si participants existent)
- [ ] Édition d'une activité par le créateur (mêmes composants que la création, respecte le verrouillage DB, notification envoyée à tous les participants acceptés pour tout champ modifié) — **DEFERRED from Sprint 3, build when join mechanics exist (Sprint 4) so field locking can be tested with real participants**
- [ ] Mes activités — liste des activités créées (contenu réel du tab, remplace le placeholder Sprint 1)

**Livrable :** Création et publication d'une activité complète.

---

## Sprint 4 — Rejoindre une activité
**Objectif :** La mécanique core BlaBlaCar fonctionne — demande, acceptation, mur.

- [ ] Toast system — feedback visuel immédiat pour les actions utilisateur (bibliothèque `burnt` : toasts natifs iOS/Android, léger, compatible Expo). Toasts sur : création d'activité, rejoindre/quitter, accepter/refuser participant, annulation. Complète les notifications persistantes — le toast confirme l'action locale, la notification informe les autres utilisateurs.
- [ ] Bouton "Rejoindre" (public — accès direct)
- [ ] Bouton "Demander à rejoindre" (sur acceptation)
- [ ] Fonction Postgres join_activity (concurrent join protection avec FOR UPDATE, vérifie status IN ('published','in_progress'), vérifie user != creator, vérifie user not blocked by creator — voir SECURITY.md "Chaîne d'autorisation")
- [ ] Rate limiting sur les demandes (max 10/heure)
- [ ] Notifications persistantes (table notifications, read/unread) + écran inbox notifications + tap-to-navigate vers l'écran concerné + bell icon dans le header bar (global, toutes les screens) avec badge unread count
- [ ] Notification créateur : nouvelle demande
- [ ] Interface gestion des demandes (côté créateur)
- [ ] Accepter / refuser une demande (vérifie activity status IN published/in_progress — voir SECURITY.md "Chaîne d'autorisation")
- [ ] Notification participant : accepté / refusé
- [ ] Accès au mur après acceptation
- [ ] Mur d'événement (wall_messages, cursor pagination, Supabase Realtime)
- [ ] Fonction Postgres message creation (rate limiting : 1/minute — mur = coordination, pas chat)
- [ ] Activités privées par lien (UUID v4, mécanisme technique — gate Premium appliquée en Sprint 6)
- [ ] Quitter une activité (Postgres function — vérifie participation status = accepted OU pending, interdit si removed, vérifie activity status IN published/in_progress. Direct DELETE bloqué par RLS. Place libérée si accepted, demande annulée si pending, accès mur révoqué)
- [ ] Retirer un participant accepté (côté créateur — vérifie que le participant n'est pas le créateur, status → removed, notification envoyée, accès mur révoqué, removal est final : un participant removed ne peut pas être re-accepté pour la même activité)
- [ ] Annulation d'une activité par le créateur (status → cancelled depuis published ou in_progress uniquement, notification à tous les participants acceptés)
- [ ] Mes activités — liste des activités rejointes (vue `my_joined_activities` : activités où user a une participation accepted et n'est pas créateur)
- [ ] Mes activités — onglets À venir / Terminées (filtre sur starts_at vs now, couvre créées ET rejointes)
- [ ] Mes activités — filtres par sport et par date (recherche/filtre dans la liste)
- [ ] Ajout `notification_preferences` au modèle user
- [ ] Ajout `left_at TIMESTAMPTZ` sur participations (capture le moment du retrait — nécessaire pour le calcul futur de pénalité < 12h, donnée irrecuperable si non capturée maintenant)
- [ ] Édition d'une activité par le créateur (mêmes composants que la création, respecte le verrouillage DB, notification envoyée à tous les participants acceptés pour tout champ modifié) — **DEFERRED from Sprint 3**

**Livrable :** Flow complet créer → demander → accepter → chatter. (Sprint le plus lourd — prévoir plus de temps)

---

## Sprint 5 — Profil utilisateur
**Objectif :** Un profil complet et consultable.

- [ ] Édition du profil (display_name, bio, sports, niveaux)
- [ ] Page profil public (selon matrice de visibilité SECURITY.md)
- [ ] Stats agrégées sur le profil public (nombre d'activités complétées, sports pratiqués, membre depuis — pas d'historique détaillé visible par les autres, protection vie privée)
- [ ] Consultation du profil d'un autre utilisateur + noms/avatars tappables → profil public partout dans l'app (popup, page événement, mur, gestion demandes)
- [ ] Bloquer un utilisateur (UI sur le profil — utilise la table blocked_users existante)
- [ ] Bouton "Envoyer un message" sur le profil d'un autre utilisateur (navigue vers placeholder/coming soon, fonctionnel en Sprint 7)
- [ ] Lien profil → page événement archivée (soft delete / lecture seule)
- [ ] Upload avatar (expo-image-picker pour sélection, expo-image pour affichage, EXIF stripping, storage policy, validation magic bytes, 5MB max)

**Livrable :** Profil complet, consultable et éditable.

---

## Sprint 6 — Messagerie privée
**Objectif :** Les utilisateurs peuvent se contacter en privé.

- [ ] Table `conversations` (migration — id, user_1, user_2, last_message_at, created_at, UNIQUE ordered pair, CHECK user_1 != user_2) pour listing efficace + rate limiting création de conversations (max 10 nouvelles par heure)
- [ ] Liste des conversations (triée par recency, dernier message, avatar, badge unread count)
- [ ] Activation du bouton "Envoyer un message" de Sprint 5 (crée ou navigue vers conversation existante)
- [ ] Conversation privée entre deux utilisateurs (cursor pagination)
- [ ] Fonction Postgres message creation privé (rate limiting : même pattern que wall messages)
- [ ] Notifications nouveaux messages
- [ ] Badge unread sur l'onglet Messagerie
- [ ] Supabase Realtime (RLS vérifié sur les channels privés — vérifier que le blocage bidirectionnel empêche l'envoi)
- [ ] Édition / suppression de messages via fonctions Postgres (edited_at, deleted_at — couvre wall_messages ET private_messages. Pas de client UPDATE/DELETE direct — empêche tampering user_id/activity_id. Vérifie auteur + activity status)

**Livrable :** Messagerie privée fonctionnelle.

---

## Sprint 7 — Modèle économique
**Objectif :** Les tiers Free / Premium / Pro sont fonctionnels.

- [ ] Intégration Stripe (abonnements via Supabase Edge Function + webhook signature verification + idempotency : stocker les event IDs traités, ignorer les doublons) + ajout `stripe_customer_id` et `subscription_status` (active/past_due/cancelled) au modèle user
- [ ] Tier Premium — création illimitée, activités privées par lien (gate sur le mode de visibilité), badge "Vérifié" sur profil/pins/popups
- [ ] Flow demande compte Pro (soumission documents — bucket `pro-documents` avec policy admin-only read)
- [ ] Validation manuelle Pro (écrans admin dans l'app, gatés par `is_admin`)
- [ ] Badge Pro "Guide Professionnel Vérifié" sur profil, pins et pop-ups (distinct du badge Premium)
- [ ] Vitrine Pro — liens externes, certifications
- [ ] Mise en avant sur la carte (Premium)

**Livrable :** Monétisation fonctionnelle.

---

## Sprint 8 — Polish & Launch prep
**Objectif :** L'app est prête pour un premier lancement public.

- [ ] Notifications push (Expo Push Notifications, contenu respectant la vie privée, gestion push receipts : clear push_token sur DeviceNotRegistered) — **DEFERRED from Sprint 4**
- [ ] Score de fiabilité — `confirmed_present` sur participations (confirmation créateur post-activité), ratio présences/inscriptions, pénalité annulation < 12h, no-show tracking. Affiché sur profil (emoji 🟢🟡🔴 ou pourcentage). Transitions automatiques de statut nécessaires pour déclencher le flow de confirmation.
- [ ] Badges de réputation — attribués par les co-participants post-activité (bon leader, fun, ponctuel, agressif...). Seuils positifs 5+, négatifs 15+. Fenêtre 48h post-activité. Table `reputation_votes` avec UNIQUE(voter_id, voted_id, activity_id, badge_key). Affichés sur profil public.
- [ ] Badges trophées — automatiques, basés sur des compteurs DB. Nouveau membre (0-4), Confirmé (10+), Expérimenté (30+), Vétéran (75+ activités complétées). Badges sport après 20 sorties dans un sport spécifique (ex: "Grand Grimpeur"). Table `user_trophies`, calcul pur DB.
- [ ] Transitions automatiques de statut des activités (pg_cron ou Edge Function : published → in_progress quand starts_at atteint, in_progress → completed quand starts_at + duration atteint, published → expired quand starts_at + 2h passé sans participants) — nécessaire pour déclencher score de fiabilité + badges
- [ ] Table reports + UI signalement d'un utilisateur, d'une activité ou d'un message (wall + privé)
- [ ] Écran admin modération (liste des reports, review du contenu signalé, actions : dismiss ou suspendre — étend l'admin Sprint 6)
- [ ] Modération : suspension d'utilisateur (utilisant suspended_at)
- [ ] Écran Paramètres (gestion préférences notifications, gestion abonnement, suppression de compte, déconnexion avec clear push_token AVANT signOut, information RGPD droit d'accès — comment demander l'export de ses données personnelles)
- [ ] Suppression de compte (RGPD — Settings → re-authentification → double confirmation → Supabase Edge Function avec service_role pour supprimer auth.users + stratégie par table selon SECURITY.md → redirect écran d'accueil)
- [ ] CGU et Politique de confidentialité (textes + URL publique hébergée pour le Play Store)
- [ ] API key restrictions (Google Places, Mapbox — package signature — à faire avant tout test externe, pas seulement avant le Play Store)
- [ ] Keystore backup sécurisé
- [ ] Android App Links (deep links vérifiés par domaine — remplace/complète le custom scheme, prévention phishing)
- [ ] App icon + splash screen (selon design system UX_UI.md)
- [ ] Optimisations performances carte
- [ ] Tests end-to-end
- [ ] Préparation Play Store (screenshots, description, catégorie, content rating questionnaire, déclaration âge 18+)
- [ ] Publication Google Play Store

**Livrable :** App publiée sur le Play Store.

---

## Backlog futur (post-launch)

### Features V2
- iOS (Apple Store)
- Filtres avancés sur la carte
- Système d'amis / réseau
- Suggestions d'activités basées sur le profil
- Partage d'activité sur réseaux sociaux
- Mode hors ligne (carte Mapbox offline)
- Sentry / error tracking
- Analytics (Mixpanel ou équivalent)
- Certificate pinning (protection MITM avancée)
- GPS spoofing detection
- CAPTCHA à l'inscription (protection anti-bot à grande échelle)
- Flux Jour J complet (partage position temps réel, confirmation géolocalisée de présence, alerte no-show, rayon de géofence configurable — voir DAY_OF_ACTIVITY.md)
- Score de présence (ratio présences/inscriptions, pénalité annulation < 12h, confirmation créateur post-activité — dépend du flux Jour J)
- Badges de réputation communautaire (attribués par les co-participants, seuils positifs 5+, négatifs 15+, fenêtre 48h post-activité — voir REPUTATION_BADGES.md)
- Vote d'annulation de groupe (2/3 pour annuler sans malus — voir ACTIVITY_MANAGEMENT.md)
- Liste d'attente automatique quand activité complète
- Alertes personnalisées (sport, localisation + rayon, niveau — notification quand une activité correspondante est créée)
- `confirmed_present` BOOLEAN sur participations (confirmation créateur post-activité — nécessaire pour score de présence)

### Features V3
- Élargissement aux activités non sportives (théâtre, cinéma, jeux)
- Tier Pro — paiement intégré in-app avec commission Junto
- Vérification d'identité avancée
- API pour clubs et associations sportives
- Tableau de bord analytics pour les Pros
