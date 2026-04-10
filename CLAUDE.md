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
- **All functions are SECURITY DEFINER** + `SET search_path = public`. Authorization chains are the ONLY defense.
- **Whitelist triggers on users + activities** — force privileged columns to OLD values. New columns protected by default.
- **Generic error messages only** — "Operation not permitted", never reveal implementation details.

## When to Read Which Doc

**BACKLOG.md task descriptions contain security requirements** (authorization chain references, specific constraints, edge cases). Always read the full task description before starting — don't just read the title.

| I'm about to... | Read first |
|-----------------|-----------|
| Start any work | This file (auto-loaded) + `BACKLOG.md` task description |
| Start a new sprint | `BACKLOG.md` + `WORKING_MODE.md` |
| Write a migration / create a table | `SECURITY.md` → "Pattern migration obligatoire" + "Matrice RLS complète" (for this table) + "Contraintes UNIQUE et CHECK" + "Stratégie de suppression par table" + "Colonnes privilégiées" |
| Add a column to an existing table | `SECURITY.md` → "Colonnes privilégiées" (add to whitelist trigger if privileged) |
| Write a Postgres function | `SECURITY.md` → "Chaîne d'autorisation complète par fonction" (for this function) + "SECURITY DEFINER" + "Exposition des fonctions via PostgREST" |
| Write a function that rate-limits | `SECURITY.md` → "Rate Limiting" (for limits) + "Intégrité des données" (advisory locks) |
| Build a screen or component | `UX_UI.md` for design + `PRODUCT.md` for behavior |
| Build a query that shows user info | Always JOIN on `public_profiles`, not `users`. See "Limitation RLS : colonnes" |
| Work on notifications | `SECURITY.md` → "Notifications push — contenu" |
| Work on blocking | `SECURITY.md` → "Blocage — directionnalité" |
| Work on storage / upload | `SECURITY.md` → "Storage" (buckets, policies, validation) |
| Work on user deletion | `SECURITY.md` → "Suppression de compte — Edge Function" + "Stratégie de suppression par table" |
| Work on tier changes / Stripe | `SECURITY.md` → "Changement de tier" + "Stripe webhook idempotency" |
| Set up Supabase config | `SECURITY.md` → "Configuration Supabase" |
| Make an architectural decision | `DECISIONS.md` — check if already decided, log new ones |
| Doubt how we work | `WORKING_MODE.md` |

## References
- Product definition → `PRODUCT.md`
- Tech stack & architecture → `TECH_STACK.md`
- UX/UI design system → `UX_UI.md`
- Development process & conventions → `WORKING_MODE.md`
- Security model → `SECURITY.md`
- Sprint backlog → `BACKLOG.md`
- Technical decisions log → `DECISIONS.md`

## Stack (quick reference)
- React Native + Expo + TypeScript
- Expo Router (file-based routing, auto deep linking, typed routes)
- TanStack Query (server state) + Zustand (UI state only)
- React Hook Form + Zod (forms + validation)
- Supabase (Postgres + PostGIS + Auth + Realtime + Storage)
- Mapbox Outdoors + Google Places API
- day.js (dates) + expo-image (images)
- i18n: react-native-i18next (FR + EN)

## Code Conventions (quick reference)
- Files/folders: kebab-case
- Components: PascalCase (`ActivityCard.tsx`)
- Hooks: `useX` (`useActivities.ts`)
- Stores: `xStore` (`activityStore.ts`)
- Services: `xService` (`activityService.ts`)
- Colors/spacing/typography: always from `@/constants/theme` — never hardcoded
- Imports: always use path aliases (`@/components/...`)
- Commit format: conventional commits, double `-m` — see `WORKING_MODE.md` for prefixes and examples
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
9. GRANT/REVOKE appropriate permissions (no anon GRANT on users table)
10. Generate updated TypeScript types after migration
11. Update seed data script

## Before Creating Any Function
1. Read the authorization chain in SECURITY.md for this function — if not documented yet, define it and add it before coding
2. **Present the authorization chain to Scott before coding** — list every check the function will perform. Scott validates. This is mandatory, not optional.
3. Start with auth check (`auth.uid() IS NULL`) + suspension check (`suspended_at IS NOT NULL`)
4. Include ALL checks from the authorization chain — there is no RLS backup
5. Use `SECURITY DEFINER` + `SET search_path = public`
6. Hardcode privileged fields (status, creator_id, created_at) — never accept from client
7. Use generic error messages only ("Operation not permitted")
8. Use advisory locks where needed for race conditions (rate limiting)
9. Use `set_config('junto.bypass_lock', 'true', true)` if the function needs to modify trigger-protected fields
10. REVOKE EXECUTE from anon. Internal functions: REVOKE from authenticated too.
11. Add the function to the SECURITY.md function classification table

## Before Any Feature
1. Read `BACKLOG.md` task description (contains security requirements and edge cases)
2. Read `PRODUCT.md` for business rules + `UX_UI.md` for design — verify behavior and appearance
3. Present approach to Scott (what, how, which files)
4. Wait for explicit validation
5. Code the feature
6. Commit with conventional commit format (see `WORKING_MODE.md` for prefixes/examples)
7. Scott tests on Expo dev build
8. Iterate if needed
9. Merge to main only after Scott's validation

## Tables with NO direct client writes
All operations via SECURITY DEFINER functions only:
- `users` (INSERT) — trigger only
- `notifications` (INSERT, DELETE)
- `wall_messages` (INSERT, UPDATE, DELETE)
- `private_messages` (INSERT, UPDATE, DELETE)
- `participations` (INSERT, UPDATE, DELETE)
- `conversations` (INSERT, UPDATE, DELETE)
- `reviews` (INSERT, UPDATE, DELETE)
