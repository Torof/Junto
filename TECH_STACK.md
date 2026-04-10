# Junto — Stack Technique

## Vue d'ensemble
Stack orientée MVP rapide, maintenable et évolutive. Tous les choix favorisent la vitesse de développement sans sacrifier la capacité à scaler ensuite.

---

## Frontend

### React Native + Expo
- **Pourquoi :** Développeur familier avec React/TypeScript, MVP Android en priorité, Expo simplifie le setup et le testing
- **Plateforme MVP :** Android uniquement
- **Plateforme V2 :** iOS via Expo (même codebase)
- **Build :** Expo custom dev build (requis pour Mapbox, Expo Go non compatible)

### TypeScript
- Typage strict sur tout le projet
- Pas de JavaScript pur, pas de `any`

### Expo Router
- **Pourquoi :** Routing file-based (comme Next.js), deep linking automatique depuis la structure de fichiers, routes typées nativement, solution officielle Expo
- **Remplace :** Configuration manuelle de React Navigation, setup deep linking manuel, typage de routes manuel

---

## State Management

### TanStack Query — Server State
- **Pourquoi :** Gère automatiquement loading, error, caching, background refetching, pagination, cache invalidation
- **Usage :** Toutes les données serveur (activities, users, messages, participations, sports, notifications)
- **Avantage clé :** Élimine le boilerplate massif que Zustand seul imposerait pour chaque entité

### Zustand — UI State
- **Pourquoi :** Léger, simple, suffisant pour l'UI state
- **Usage :** Filtres carte, vue active, toggles UI, région carte courante
- **Règle :** Zustand ne contient JAMAIS de données serveur

### Architecture state
```
TanStack Query          Zustand
(server state)          (UI state)
├── activities          ├── map filters
├── messages            ├── selected sport
├── user profiles       ├── current map region
├── participations      ├── active tab
├── sports list         └── UI toggles
└── notifications
```

---

## Formulaires

### React Hook Form + Zod
- **Pourquoi :** Flow création en 4 étapes, édition profil, paramètres — gérer ça avec useState serait chaotique
- **React Hook Form :** Gestion multi-step native, performant, léger
- **Zod :** Schémas de validation partagés entre formulaires client et cohérents avec les contraintes DB

```typescript
const activitySchema = z.object({
  title: z.string().min(3).max(100),
  maxParticipants: z.number().min(2).max(50),
  startsAt: z.date().refine(d => d > new Date(), "Must be in the future"),
  visibility: z.enum(['public', 'approval', 'private_link', 'private_link_approval']),
})
```

---

## Backend / BaaS

### Supabase
- **Pourquoi :** Postgres + Auth + Realtime + Storage en un seul service
- **PostGIS** intégré — crucial pour les requêtes géospatiales (recherche par rayon)
- **Auth :** Google login, email/password, vérification téléphone
- **Realtime :** Notifications et chat en temps réel
- **Storage :** Photos profil (bucket public), documents Pro (bucket privé). Pas de stockage GPX — parsé côté client, coordonnées en PostGIS.
- **Migrations :** Versionnées dans git (`/supabase/migrations/`)
- **Types auto-générés :** `supabase gen types typescript` après chaque migration

---

## Cartes

### Mapbox (style "Outdoors")
- **Pourquoi :** Meilleure customisation visuelle, style Outdoors avec relief et courbes de niveau, moins cher que Google Maps, offline mode, données OpenStreetMap riches en sentiers et chemins
- **Usage :** Affichage carte principale, pins activités, tracés d'itinéraires, relief
- **Library React Native :** `@rnmapbox/maps`

### Google Places API
- **Pourquoi :** Base de données POI la plus complète au monde pour la recherche d'adresses
- **Usage :** Recherche et autocomplétion d'adresses uniquement (lors de la création d'activité)
- Pas utilisé pour l'affichage de carte

---

## Dates

### day.js
- **Pourquoi :** App internationale avec événements géolocalisés cross-timezone. JavaScript `Date` natif est peu fiable pour la gestion de fuseaux horaires.
- **Taille :** 2KB, impact négligeable
- **Usage :** Manipulation de dates, conversion timezone, affichage relatif ("dans 2h")
- **Règle :** Toutes les dates en UTC dans la base, converties en local pour l'affichage

---

## Images

### expo-image
- **Pourquoi :** Drop-in replacement de `Image` avec cache intégré, placeholders blur, transitions. Le composant `Image` natif n'a pas de cache — chaque scroll re-fetch les photos.
- **Usage :** Partout où une image est affichée (avatars, photos activité, icônes sport)
- **Règle :** Ne jamais utiliser le composant `Image` de React Native

---

## Internationalisation

### react-native-i18next
- **Pourquoi :** Retrofitter l'i18n sur 30+ écrans coûte des semaines. Le setup initial coûte 5 min par écran.
- **Langues MVP :** Français + Anglais
- **Structure :** `/src/i18n/fr.json`, `/src/i18n/en.json`
- **Règle :** Toute chaîne visible par l'utilisateur passe par `t('key')`

---

## Notifications
- **Expo Push Notifications** — natif, simple, gratuit
- **Table `notifications` en base** — stockage persistant, inbox, read/unread
- Cas d'usage : demande de participation, acceptation/refus, nouveau message

---

## Besoins cartographiques détaillés

### Affichage des activités
- Carte Mapbox Outdoors comme fond
- Pins géolocalisés par activité
- Clustering sur zones denses
- Distinction visuelle : en cours / bientôt / à venir

### Création d'une activité
- Poser un pin de point de départ
- Poser un pin de point de rendez-vous
- Tracer un itinéraire simple (points reliés)
- Import GPX optionnel (Strava, Komoot, Garmin) — parsé côté client avec validation XML sécurisée, coordonnées stockées en PostGIS (pas de fichier GPX conservé)

### Lecture d'une activité
- Visualisation du tracé sur la carte
- Pins départ et rendez-vous visibles
- Relief lisible via style Outdoors

---

## Architecture base de données (Supabase / Postgres + PostGIS)

### Tables Sprint 1
- `users` — profils utilisateurs (modèle complet dès Sprint 1)
- `activities` — événements sportifs
- `participations` — demandes et acceptations
- `sports` — référentiel des sports (table de référence, pas de strings hardcodés)
- `wall_messages` — messages du mur d'événement
- `private_messages` — messagerie privée (table séparée pour RLS simple)
- `notifications` — notifications persistantes (push + inbox)
- `blocked_users` — utilisateurs bloqués (affecte les politiques RLS)

### Géospatial
- Colonnes `geometry` PostGIS sur les activités
- Requêtes `ST_DWithin` pour la recherche par rayon (cap à 100km max)
- Index spatial GIST pour les performances

### Règles
- Toutes les timestamps en UTC (`TIMESTAMPTZ`)
- Contraintes sur chaque colonne (`NOT NULL`, `CHECK`, `UNIQUE`)
- RLS sur chaque table, écrite à la création
- Types auto-générés après chaque migration
- Seed data script reproductible (`/supabase/seed.sql`)

---

## Paiement (futur — pas MVP)
- Stripe — pour les abonnements Premium et Pro
- `stripe_customer_id` ajouté au modèle user au Sprint 6
- Pas implémenté dans le MVP

---

## Résumé

| Couche | Techno | Raison |
|--------|--------|--------|
| Mobile | React Native + Expo | Familier, cross-platform, rapide |
| Langage | TypeScript strict | Typage, maintenabilité |
| Routing | Expo Router | File-based, deep linking auto, typé |
| Server State | TanStack Query | Cache, refetch, loading/error auto |
| UI State | Zustand | Simple, léger, UI uniquement |
| Forms | React Hook Form + Zod | Multi-step, validation, typé |
| Backend | Supabase | All-in-one, PostGIS, gratuit MVP |
| Carte | Mapbox Outdoors | Customisation, outdoor, prix |
| Recherche lieu | Google Places API | POI database imbattable |
| Images | expo-image | Cache, performance, drop-in |
| Dates | day.js | Timezone-safe, léger |
| i18n | react-native-i18next | FR + EN dès le départ |
| Notifications | Expo Push + table DB | Push + persistence |
