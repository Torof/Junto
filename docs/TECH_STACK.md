# Junto — Stack Technique

À jour au 28 avril 2026. Stack orientée MVP rapide, maintenable et évolutive.

## Frontend

### React Native + Expo (SDK 54)
- Plateforme cible : Android (priorité), iOS (codebase identique)
- Build : Expo custom dev build (`expo-dev-client`) — Mapbox + TaskManager + geofencing nécessitent du code natif
- OTA via EAS Update (channel `preview` pour le dev, `production` pour le store)

### TypeScript strict
- Pas de `any`, pas de JavaScript pur

### Expo Router
- File-based, deep linking automatique, routes typées
- Custom scheme `junto://` + universal links sur `getjunto.app` (`/activity/*`, `/invite/*`)

---

## State Management

### TanStack Query — server state
- Cache, refetch, invalidation automatiques
- Toutes les données serveur (activities, users, messages, participations, sports, notifications)

### Zustand — UI state uniquement
- Filtres carte, sélections UI, état tutoriel, préférences thème
- **Règle :** ne contient JAMAIS de données serveur

### Architecture
```
TanStack Query          Zustand
(server state)          (UI state)
├── activities          ├── map filters (sport, level, date, visibility)
├── messages            ├── theme preference
├── user profiles       ├── map style
├── participations      ├── tutorial state
├── reputation badges   └── (no server data)
├── peer review state
└── notifications
```

---

## Validation

### Zod (type derivation only)
- Schéma `activityFormSchema` dans `src/types/activity-form.ts`
- Sert exclusivement à dériver le type `ActivityFormData` via `z.infer<typeof activityFormSchema>`
- **La validation runtime côté client est minimale** — toute validation business est appliquée côté serveur dans des fonctions SECURITY DEFINER (la couche client est bypassable via appel API direct)
- React Hook Form retiré du stack (mig deps cleanup) — les formulaires utilisent du state inline + validation serveur

---

## Backend / BaaS

### Supabase
- Postgres 15 + PostGIS pour les requêtes géospatiales
- Auth : email/password, reset password via deep link
- Storage : `avatars` (public, path fixe `/avatars/{user_id}/avatar`), `pro-documents` (privé)
- Migrations versionnées dans `supabase/migrations/` (currently 149 migrations)
- Edge Functions dans `supabase/functions/` :
  - `send-push` — envoi push via Expo Push API, secret partagé via header
  - `delete-user` — suppression de compte avec service_role
- Types auto-générés via `supabase gen types typescript`

---

## Cartes

### Mapbox (style "Outdoors")
- `@rnmapbox/maps`
- Style Outdoors avec relief et courbes de niveau
- Affichage carte principale, pins activités, tracés d'itinéraires (`trace_geojson`)

### Google Places API
- Recherche et autocomplétion d'adresses uniquement (création d'activité)

---

## Présence — modules dédiés

Architecture multi-couches pour le flux de validation :

| Module | Rôle |
|---|---|
| `src/lib/presence-geofence-task.ts` | TaskManager headless task — wake OS sur Enter event |
| `src/hooks/use-presence-geofences.ts` | Enregistre les régions (T-2h..T+15min), initial-state check |
| `src/hooks/use-presence-geo-watcher.ts` | Foreground polling watcher (30s) avec accuracy threshold |
| `src/lib/presence-offline-cache.ts` | Queue AsyncStorage pour replay quand réseau revient |
| `src/hooks/use-presence-offline-flusher.ts` | Drain la queue sur foreground / NetInfo reconnect |

Voir `docs/DAY_OF_ACTIVITY.md` pour le flux complet.

---

## Notifications

- **Expo Push** via FCM (Android) + APNs (iOS)
- Table `push_tokens` (mig 00121) — multi-device aware, keyed sur `(user_id, device_id)` ; `device_id` persisté dans SecureStore
- Routing par type dans le trigger `push_notification_to_device` (mig 00148) : collapse_id par activity_id, suppression de certains types (in-app only), pluralization (×N) sur le slot présence
- Table `notifications` côté DB — persistance, badges, inbox

---

## Diagnostic

### Sentry
- `@sentry/react-native` — auto-consent en preview channel uniquement
- DSN via `EXPO_PUBLIC_SENTRY_DSN`
- Lat/lng exclus côté serveur (filtre `SENSITIVE_KEYS` dans `lib/sentry.ts`)
- Helper `trace(category, message, data)` pour breadcrumbs (no-op en dev)
- Catégories utilisées : `presence.geofence`, `presence.watcher`, `presence.offline`

---

## Dates

### day.js
- 2KB, timezone-safe
- **Toutes les dates en UTC dans la base, converties en local pour l'affichage**

---

## Images

### expo-image
- Cache intégré, placeholders blur, transitions
- Drop-in replacement de `Image` natif (qui n'a pas de cache)

---

## Internationalisation

### react-native-i18next
- FR + EN
- Fichiers `src/i18n/fr.json`, `src/i18n/en.json` (mirror structure)
- Pluralization automatique via suffixes `_one` / `_other` quand `count` est passé en variable
- Toute chaîne visible par l'utilisateur passe par `t('key')`

---

## Geo helpers

### `src/utils/geo.ts`
- `distanceMeters(lat1, lng1, lat2, lng2)` — haversine en mètres
- Utilisé partout sur le client (geofence checks, foreground watcher, sort des activités par distance)
- PostGIS reste l'autorité côté serveur (`ST_Distance`, `ST_DWithin`, `ST_GeomFromGeoJSON`)

---

## Architecture base de données

### Tables principales

| Table | Usage |
|---|---|
| `users` | profils utilisateurs (privé, RLS strict) |
| `public_profiles` (vue) | exposition publique des profils sans champs sensibles |
| `activities` | événements sportifs avec `location_*` PostGIS + `trace_geojson` JSONB |
| `participations` | inscriptions + `confirmed_present` + transport assignment |
| `sports` | référentiel (anon read OK) |
| `wall_messages` | messages du mur d'événement |
| `private_messages` | messagerie privée (DM) |
| `conversations` | métadonnées de conversation (status, request expiry) |
| `notifications` | inbox + push routing |
| `push_tokens` | multi-device push registration |
| `peer_validations` | votes de présence post-activité |
| `reputation_votes` | votes de badges réputation |
| `presence_tokens` | QR tokens issus par les créateurs |
| `seat_requests` | demandes de covoiturage |
| `activity_alerts` | alertes (saved searches) |
| `activity_gear` | matériel collaboratif |
| `sport_level_endorsements` | confirmation/contestation de niveau annoncé |
| `user_badge_progression` | tiers progression (joined/created/sport) |
| `blocked_users` | bidirectionnel pour DM, unidirectionnel ailleurs |
| `reports` | signalements de modération |

### Règles
- Toutes les timestamps en UTC (`TIMESTAMPTZ`)
- Contraintes sur chaque colonne (`NOT NULL`, `CHECK`, `UNIQUE`)
- RLS sur chaque table, écrite à la création (`ENABLE` + `FORCE`)
- Types auto-générés via `supabase gen types`
- Seed data dans `supabase/seed.sql`

### Géospatial
- Colonnes `geography(Point, 4326)` sur `activities.location_*`
- `trace_geojson JSONB` pour les LineStrings (parsé côté client depuis GPX, validé via CHECK)
- Requêtes `ST_DWithin` pour recherche par rayon (cap à 100km max)
- Index GIST pour les performances

---

## Paiement (futur)
- Stripe pour Premium / Pro
- Webhook idempotency : stocker `event_id` traités, traiter D'ABORD, stocker ENSUITE
- `stripe_customer_id`, `subscription_status` privilégiées (Stripe webhook only)

---

## Web

### Next.js (`web/`)
- Site marketing + bridges pour deep links (auth callback, reset-password, activity public, invite)
- Domaine : `getjunto.app`
- Hébergé sur Vercel

---

## Dépendances clés (extraites de package.json)

| Couche | Package |
|---|---|
| Mobile | `react-native@0.81.5`, `expo@~54.0.33` |
| Routing | `expo-router@~6.0.23` |
| State | `@tanstack/react-query@^5.97.0`, `zustand@^5.0.12` |
| Validation | `zod@^4.3.6` |
| Backend SDK | `@supabase/supabase-js@^2.103.0` |
| Maps | `@rnmapbox/maps@^10.3.0`, `supercluster@^8.0.1` |
| Localisation | `expo-location@~19.0.8`, `expo-task-manager@~14.0.9` |
| Notifs | `expo-notifications@~0.32.16` |
| Storage | `@react-native-async-storage/async-storage@2.2.0`, `expo-secure-store@~15.0.8` |
| Network | `@react-native-community/netinfo@11.4.1` |
| Diagnostic | `@sentry/react-native@~7.2.0` |
| Camera (QR) | `expo-camera@~17.0.10` |
| Files | `expo-file-system`, `expo-document-picker`, `expo-sharing`, `expo-image-manipulator`, `expo-image-picker` |
| UI primitives | `@gorhom/bottom-sheet`, `react-native-svg`, `react-native-qrcode-svg`, `react-native-reanimated`, `react-native-gesture-handler`, `lucide-react-native` |
| Toasts | `burnt` |
| Dates | `dayjs` |
| i18n | `i18next`, `react-i18next` |

---

## Résumé

| Couche | Techno | Raison |
|--------|--------|--------|
| Mobile | React Native + Expo SDK 54 | Cross-platform, build outils mature |
| Langage | TypeScript strict | Typage, maintenabilité |
| Routing | Expo Router | File-based, deep linking auto, typé |
| Server state | TanStack Query | Cache, refetch, loading/error auto |
| UI state | Zustand | Léger, UI uniquement |
| Validation | Zod (type only) | Schema → type ; runtime validation côté serveur |
| Backend | Supabase | Postgres + PostGIS + Auth + Storage + Edge Functions |
| Maps | Mapbox Outdoors + Google Places | Outdoor visuel, POI search |
| Présence | TaskManager + AsyncStorage offline cache | Geofence headless + replay |
| Diagnostic | Sentry | Breadcrumbs, error tracking, opt-in PII filter |
| Push | Expo Push (FCM + APNs) | Multi-device tokens table |
| Dates | day.js | Timezone-safe, léger |
| i18n | react-native-i18next | FR + EN |
