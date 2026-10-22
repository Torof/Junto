# Junto — Claude Code Instructions

## Critical Rules
- **Never code without Scott's explicit validation.** Propose first, code only after approval.
- **Never use `service_role` key in client code.** Only `anon` key, protected by RLS.
- **Never use `select('*')`.** Always explicit column selection.
- **Never auto-link URLs in user-generated text** (descriptions, messages, bio). Only Pro profile external links (explicitly defined fields) are tappable.
- **Never commit `.env`, keystores, or secrets.** Check `.gitignore` before first commit.
- **TypeScript strict — no `any`, no JavaScript.**
- **All business rules enforced at database level**, not just client-side.
- **All JOINs with user data** must use `public_profiles` view, NOT `users` table.
- **All functions are SECURITY DEFINER** + `SET search_path = public, extensions`. Authorization chains are the ONLY defense. (`extensions` because PostGIS lives there on the migrated project — a function using geography operators without it fails only at runtime. Only `postgres` can create objects in `extensions`, so it cannot be hijacked.)
- **Schema changes only through migrations** — never the dashboard table editor, never "enable extension" from the dashboard. Every object of `public`/`private` belongs to `postgres` and no extension lives in `public` (tested in `00_socle`): that is what made the old database unrepairable.
- **Never write the project host** (`*.supabase.co`) in SQL or tests — use `private.project_url()` (fail-closed when missing) / `pg_temp.host()` in tests.
- **Column protection** — `users`: true whitelist trigger (`handle_user_update`, 00510): a client can change only `display_name`, `avatar_url`, `bio`, `sports`, `notification_preferences`, `language`; every other column, including new ones, keeps its old value unless a SECURITY DEFINER function sets `junto.bypass_lock`. `activities`: no client write grant at all (00480) + `handle_activity_update` pins privileged columns against definer functions.
- **Generic errors for SENSITIVE failures** (auth, ownership, participant-status, suspension, access) — "Operation not permitted", never reveal implementation details or another user's state. **User-actionable, NON-sensitive failures** (rate limits, input validation, capacity, premium gates) may `RAISE EXCEPTION 'junto.<code>'` — a stable token the client maps to a friendly message (`errors.code.<code>`). These leak nothing exploitable (the user's own limit/input state). See SECURITY.md "Messages d'erreur".

## When to Read Which Doc

**BACKLOG.md task descriptions contain security requirements** (authorization chain references, specific constraints, edge cases). Always read the full task description before starting — don't just read the title.

| I'm about to... | Read first |
|-----------------|-----------|
| Start any work | This file (auto-loaded) + `docs/BACKLOG.md` task description |
| Start a new sprint | `docs/BACKLOG.md` + `docs/WORKING_MODE.md` |
| Write a migration / create a table | `docs/SECURITY.md` → "Pattern migration obligatoire" + "Matrice RLS complète" (for this table) + "Contraintes UNIQUE et CHECK" + "Stratégie de suppression par table" + "Colonnes privilégiées" |
| Add a column to an existing table | `docs/SECURITY.md` → "Colonnes privilégiées" (add to whitelist trigger if privileged) |
| Write a Postgres function | `docs/SECURITY.md` → "Chaîne d'autorisation complète par fonction" (for this function) + "SECURITY DEFINER" + "Exposition des fonctions via PostgREST" |
| Write a function that rate-limits | `docs/SECURITY.md` → "Rate Limiting" (for limits) + "Intégrité des données" (advisory locks) |
| Build a screen or component | `docs/UX_UI.md` for design + `docs/PRODUCT.md` for behavior |
| Build a query that shows user info | Always JOIN on `public_profiles`, not `users`. See "Limitation RLS : colonnes" |
| Work on messaging (conversations, messages, groups, invitations) | `docs/sprint-messaging.md` (unified model + validated auth chains) + `docs/SECURITY.md` → "Conversations & messagerie" + RLS matrix (`messages`/`conversation_members`/`conversations`) |
| Work on notifications | `docs/SECURITY.md` → "Notifications push — contenu" |
| Work on blocking | `docs/SECURITY.md` → "Blocage — directionnalité" |
| Work on storage / upload | `docs/SECURITY.md` → "Storage" (buckets, policies, validation) |
| Work on user deletion | `docs/SECURITY.md` → "Suppression de compte — Edge Function" + "Stratégie de suppression par table" |
| Work on tier changes / Stripe | `docs/SECURITY.md` → "Changement de tier" + "Stripe webhook idempotency" |
| Work on presence validation (geo, QR, peer review, offline replay) | `docs/DAY_OF_ACTIVITY.md` + `docs/SECURITY.md` → "Système de présence" |
| Work on badges (progression, reputation, reliability) | `docs/REPUTATION_BADGES.md` + `docs/SECURITY.md` → "Système de badges" |
| Work on push notifications routing / collapse | `docs/SECURITY.md` → "Push notifications" |
| Set up Supabase config | `docs/SECURITY.md` → "Configuration Supabase" |
| Work on admin / moderation powers | `docs/ADMIN.md` (admin role charter — powers, hard boundaries, roadmap) + `docs/SECURITY.md` → "Fonctions privilégiées admin" |
| Work on the pro side (profile, offerings, agenda, bookings) | `docs/PRO_HARDENING.md` (living checklist, lots 0-3 + open decisions) + `docs/sprint-booking.md` + `docs/SECURITY.md` → "Pro — vitrine" + "Réservations pro" |
| Make an architectural decision | `docs/DECISIONS.md` — check if already decided, log new ones |
| Doubt how we work | `docs/WORKING_MODE.md` |

## References
- Product definition → `docs/PRODUCT.md`
- Tech stack & architecture → `docs/TECH_STACK.md`
- UX/UI design system → `docs/UX_UI.md`
- Development process & conventions → `docs/WORKING_MODE.md`
- Security model → `docs/SECURITY.md`
- Admin role charter → `docs/ADMIN.md`
- Sprint backlog → `docs/BACKLOG.md`
- Technical decisions log → `docs/DECISIONS.md`

## Stack (quick reference)
- React Native + Expo SDK 54 + TypeScript strict
- Expo Router (file-based routing, auto deep linking, typed routes)
- TanStack Query (server state) + Zustand (UI state only)
- Zod (form schema; type derivation only — runtime validation lives in DB SECURITY DEFINER functions)
- Supabase (Postgres + PostGIS + Auth + Realtime + Storage + Edge Functions)
- Mapbox Outdoors + Google Places API
- day.js (dates) + expo-image (images)
- Sentry (`@sentry/react-native`) — preview-only auto-consent ; use `trace(category, message, data)` from `lib/sentry` for diagnostic breadcrumbs (lat/lng auto-redacted)
- AsyncStorage + NetInfo for offline presence cache (see `lib/presence-offline-cache`)
- TaskManager for background geofencing (see `lib/presence-geofence-task`)
- i18n: react-native-i18next (FR + EN, pluralization via `_one`/`_other` suffixes)

## Code Conventions (quick reference)
- Files/folders: kebab-case
- Components: PascalCase (`ActivityCard.tsx`)
- Hooks: `useX` (`useActivities.ts`)
- Stores: `xStore` (`activityStore.ts`)
- Services: `xService` (`activityService.ts`)
- Colors/spacing/typography: always from `@/constants/theme` — never hardcoded
- Imports: always use path aliases (`@/components/...`)
- Commit format: conventional commits, double `-m` — see `docs/WORKING_MODE.md` for prefixes and examples
- Commit language: English
- Database: UTC for all timestamps, constraints on every column, RLS on every table

## Before Creating Any Table
1. Add proper constraints (NOT NULL, CHECK, UNIQUE) — see SECURITY.md "Contraintes UNIQUE et CHECK"
2. `ENABLE ROW LEVEL SECURITY` + `FORCE ROW LEVEL SECURITY` immediately after CREATE TABLE
3. Write RLS policies immediately — see SECURITY.md "Matrice RLS complète" for this table's policies
4. Identify privileged columns — add to whitelist trigger (force to OLD)
5. Use TIMESTAMPTZ (UTC) for all time fields
6. Add `ON DELETE CASCADE` or `ON DELETE SET NULL` per SECURITY.md "Stratégie de suppression par table"
7. Include `suspended_at IS NULL` check in RLS where relevant
8. Include blocked_users filter in RLS where relevant (unidirectional for wall, bidirectional for private messages)
9. Grants: since 00502 a new table gives clients SELECT only. A direct client write needs an explicit `GRANT` **and** a write policy (rare — prefer a function). No anon grant on user data.
10. Generate updated TypeScript types after migration
11. Update seed data script

## Before Creating Any Function
1. Read the authorization chain in SECURITY.md for this function — if not documented yet, define it and add it before coding
2. **Present the authorization chain to Scott before coding** — list every check the function will perform. Scott validates. This is mandatory, not optional.
3. Start with auth check (`auth.uid() IS NULL`) + suspension check (`suspended_at IS NOT NULL`)
4. Include ALL checks from the authorization chain — there is no RLS backup
5. Use `SECURITY DEFINER` + `SET search_path = public, extensions`
6. Hardcode privileged fields (status, creator_id, created_at) — never accept from client
7. Generic "Operation not permitted" for sensitive checks; `RAISE EXCEPTION 'junto.<code>'` for user-actionable non-sensitive ones (limits/validation/capacity/premium) + add `errors.code.<code>` i18n (FR+EN)
8. Use advisory locks where needed for race conditions (rate limiting)
9. Use `set_config('junto.bypass_lock', 'true', true)` if the function needs to modify trigger-protected fields
10. Since 00511 a new function is executable by NOBODY by default (no PUBLIC/anon/authenticated EXECUTE). Client-callable RPC → `GRANT EXECUTE ON FUNCTION … TO authenticated` explicitly (never anon unless truly public). Internal / trigger functions → no grant.
11. Add the function to the SECURITY.md function classification table

## Before Any Feature
1. Read `docs/BACKLOG.md` task description (contains security requirements and edge cases)
2. Read `docs/PRODUCT.md` for business rules + `docs/UX_UI.md` for design — verify behavior and appearance
3. Present approach to Scott (what, how, which files)
4. Wait for explicit validation
5. Code the feature
6. Commit with conventional commit format (see `docs/WORKING_MODE.md` for prefixes/examples)
7. Scott tests on Expo dev build
8. Iterate if needed
9. Merge to main only after Scott's validation

## Tables with NO direct client writes
Every public table has FORCE RLS. A client write needs a table/column grant AND a write policy; many older tables still carry the default `authenticated` INSERT/UPDATE/DELETE grant but have no write policy, so RLS refuses the write. Since 00502, new tables get SELECT only by default. All writes below go through SECURITY DEFINER functions or triggers (verified against the live DB, 2026-10-21):
- `activities` — `create_activity`, `update_activity`, `update_activity_trace`, `cancel_activity`, lazy/cron transitions (no client grant at all)
- `participations` — `join_activity`, `leave_activity`, `accept/refuse_participation`, `remove_participant`, invitation RPCs, `set_participation_transport`, `confirm_presence_via_*`
- `messages` — `send_message` (+ `send_wall_message`/`send_private_message` wrappers), `share_*_message`, `edit_message`, `delete_message`, seat/booking/contact seed messages
- `conversations` — contact-request RPCs, `create_group`/`rename_group`/`leave_group`, channel RPCs, `create_activity_conversation` trigger; SELECT also revoked (curated RPCs only, 00352)
- `conversation_members` — derived from participations (`sync_activity_membership`), groups, channels; own row via `mark_conversation_read`/`set_conversation_hidden`
- `channels`, `channel_bans` — `create_channel`, `close_channel`, `set_channel_photo`, `remove_channel_member`
- `discovery_availabilities` — `upsert_dispo`, `activate_dispo`/`deactivate_dispo`
- `seat_requests` — `request_seat`, `accept/decline_seat_request`, `cancel_pending_seat_request`, `cancel_accepted_seat`
- `activity_gear` / `activity_gear_missing` — `set_activity_gear`, `add/remove_missing_gear`
- `reputation_votes` — `give/revoke_reputation_badge`, `set_sport_level`
- `presence_tokens` — `create_presence_token`
- `push_tokens` — `register_push_token`, `revoke_push_token_for_device`
- `user_badge_progression` — `award_badge_progression` (trigger)
- `gpx_traces` — `create/rename/delete_gpx_trace`
- `favorites` — `add_favorite`/`remove_favorite`
- `pro_profiles` — `register_as_pro`/`update_pro_profile`/`resubmit_pro_application`/`unregister_as_pro`, pin setters, admin `approve_pro`/`reject_pro`
- `pro_offerings` — `create/update/delete_pro_offering`, `set_offering_details`
- `pro_profile_photos` / `pro_offering_photos` / `pro_community_photos` — `add/remove/reorder_*` RPCs
- `pro_reviews` / `offering_reviews` — `create/update/delete/reply_to_*_review`
- `pro_availabilities` — `set_pro_availability(_bulk)`
- `bookings` — `create_booking`, `create_manual_booking`, accept/decline/cancel RPCs, `set_booking_participant_info`
- `users` (INSERT) — `handle_new_user` trigger + `ensure_user_row`; `notifications` (INSERT, DELETE) — `create_notification` + `notify_*`; `reports` (INSERT) — `create_report`, DELETE never; `activity_alerts` (INSERT/UPDATE) — `create_alert`
- Internal tables, no client grant: `rate_events`, `late_cancels`, `invite_grants`, `invitation_declines`, `conversation_departures`, `message_original_content`, `contact_qr_tokens`, `contact_qr_scans`, `contact_removal_archive`, `map_broadcasts`, `snap_trail_calls`, `trace_elevation_calls`, `admin_actions`, `banned_email_hashes`. No write policy: `app_config` (only `admin_set_demo_mode`), `gear_catalog` (migrations only)

**Deliberate direct client writes** (grant + RLS policy): `users` UPDATE own row (`handle_user_update` pins privileged columns: client can change `display_name`, `avatar_url`, `bio`, `sports`, `notification_preferences`, `language`) · `blocked_users` INSERT/DELETE where `blocker_id = auth.uid()` · `notifications` UPDATE own (`handle_notification_update` keeps only `read_at`) · `activity_alerts` DELETE own · `reports` UPDATE by admins · `sports` INSERT/UPDATE/DELETE by admins.
