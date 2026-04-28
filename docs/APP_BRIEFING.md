# Junto — App Briefing

> A self-contained orientation document for any collaborator (human or AI) joining a Junto conversation fresh. This is not a spec or a roadmap — it's context. Repo: https://github.com/Torof/Junto

**Last updated:** 2026-04-28
**State:** Pre-launch, preview builds distributed via APK to a small dogfooding circle. Web companion deployed at `getjunto.app`.

---

## 1. Elevator pitch

Junto is **BlaBlaCar for outdoor sports activities**. A geolocated mobile app where people create spontaneous outings (climbing sessions, hikes, paragliding flights, canyon trips, ski tours, slackline meetups, etc.) and let nearby strangers request to join.

The core value prop in one sentence: **"Find outdoor sports partners near you, today."**

Target user archetype: an intermediate-to-advanced outdoor practitioner — the kind of person who has skills but lacks a consistent partner. Someone who thinks by *activity* ("I want to climb this weekend") rather than by *social network* ("who's free?"). French-speaking and English-speaking markets, mobile-first, Android before iOS.

The product is intentionally narrow at v1: outdoor sports, real-time coordination, people-to-people. Not a Meetup clone, not a fitness tracker, not a social network.

---

## 2. State of the app (2026-04-28)

**Status:** All 8 planned sprints substantially shipped + several systems beyond (presence V3, badge progression V2, offline geo replay, contact/seat-request expiry, simplified notif spine). `docs/BACKLOG.md` was rewritten 2026-04-26 to reflect actual remaining work.

**Distribution today:**
- Android APK built with EAS (`preview` profile, channel `preview`), distributed to dogfooding testers.
- Web companion at `getjunto.app` — Vercel-hosted Next.js site for marketing + auth deep-link bridges (email confirm callback, reset-password) + share previews.
- iOS: codebase ready, not yet built or submitted (deferred until user base meaningful).
- Play Store: not yet submitted.
- Supabase hosted (not local Docker). 149 migrations in [supabase/migrations/](https://github.com/Torof/Junto/tree/main/supabase/migrations).

**Audience today:** a handful of testers Scott knows personally. Not public.

---

## 3. Product principles (the non-obvious choices)

These are the decisions that shape how Junto feels and behaves. Each came from a deliberate tradeoff — worth understanding before proposing changes that contradict them.

### Safety-first framing, not community-first
Junto connects strangers in remote outdoor settings. Physical risk is real (climbing falls, avalanches, exhaustion). Every product decision weights safety over engagement. Examples: presence verification, late-cancel penalties, reputation badges negative path (15+ negative votes trigger visibility), generic error messages (no info leakage that enables social engineering).

### No public history of where you've been
The public profile shows aggregate stats only — "42 completed activities, climbing and paragliding, member since 2025" — never a list of specific activities with dates and locations. Junto refuses to leak movement patterns. A detailed history could tell a stalker when and where you hike. See [`docs/DECISIONS.md`](https://github.com/Torof/Junto/blob/main/docs/DECISIONS.md) entry "2026-04-11".

### Presence verification as a trust primitive
Activities can require participants to confirm presence on-site — via geofenced check-in (150m radius of start/meeting/end), QR scan from the creator, or creator override. Presence data feeds the reliability score. Per-activity opt-out exists for casual outings (gym climbing, coffee) where verification would be theater.

### Unidirectional blocking
If A blocks B: B cannot see A's activities, messages, or profile. A still sees B's presence in shared contexts. This prevents B from working around the block and protects A without advertising that A blocked them. See [`docs/SECURITY.md`](https://github.com/Torof/Junto/blob/main/docs/SECURITY.md) "Blocage — directionnalité".

### Messaging is for coordination, not chat
Wall messages rate-limited to 1/minute. Private messages exist but are deprioritized. Junto is not a messaging app — it's an activity coordination app that happens to need messaging. Keeping coordination primary discourages the product drifting into Discord territory.

### No clickable user-generated text
Descriptions, wall posts, bio — none auto-link URLs. Only Pro profile external links (explicit fields) are tappable. Prevents phishing at minimal UX cost.

### Business rules live in the database
Every write goes through a `SECURITY DEFINER` Postgres function. No client-side RLS backup. Authorization chains are documented per function in SECURITY.md. See the "Before Creating Any Function" checklist in [`CLAUDE.md`](https://github.com/Torof/Junto/blob/main/CLAUDE.md).

### Strings and numbers guessed, not validated
Many thresholds (reputation badge at 5+ positive votes, 15+ negative; late-cancel window of 12h; geofence of 150m; rate limits) are first-principles guesses. They will be wrong. Data from real usage will calibrate them.

---

## 4. What's shipped — feature by feature, with rationale

### Authentication
- Email/password via Supabase Auth (Google OAuth deferred).
- Login screen redesigned (topo SVG bg, sign-in / register tab pills, password show/hide, ToS checkbox at signup, inline errors).
- Random display name generated on signup (modifiable later).
- Date of birth capture + 18+ age gate.
- ToS + Privacy Policy acceptance tracked as timestamps.
- Reset password via deep link: web bridge at `getjunto.app/auth/reset-password` redirects to `junto://reset-password` ; AuthGate pins user to recovery screen.
- Email templates Junto-branded (Bienvenue + Réinitialiser).

**Why:** Email/password is the lowest-friction path with the broadest reach. Random name gets users into the app without forcing identity up front. Reset-password deep link avoids round-trip to a hosted Supabase form.

### Map & discovery
- Mapbox Outdoors base layer + clustering + fly-to on pin tap.
- Pins show sport icon + participant-joined count (green until full, red when full).
- Bottom sheet with activity list below the map (pull to expand).
- Filters: sport, date, distance.
- Deep link + share support — both custom scheme (`junto://activity/<id>`) and Android App Links (`https://junto.app/activity/<id>`).

**Why Mapbox Outdoors:** trail visibility. Google Maps shows roads; outdoor practitioners need topo.

### Activity creation (4-step flow)
1. Sport + title + description + level + max participants (NULL = open activity, soft-cap 50) + distance/D+ when sport uses them.
2. Start / meeting / end / objective pins + date/time/duration + optional GPX trace import.
3. Visibility mode (public / approval / private-link / private-link-approval) + presence verification toggle.
4. Review + publish.

Built with inline state in a Zustand `create-store`. Zod schema in `src/types/activity-form.ts` derives the type via `z.infer` (runtime validation lives in DB SECURITY DEFINER functions).

**Why 4 steps:** activity creation has 10+ fields; a single form overwhelms. Steps let the user commit progressively.

### Visibility modes (4)
- **Public:** on map, anyone can join directly.
- **Approval:** on map, join requires creator approval.
- **Private link:** not on map, shared via UUID token.
- **Private link + approval:** not on map, shared via UUID token, still requires approval.

**Why 4 modes:** public is for discovery, approval is for quality control, private modes are for friend groups who want to use the coordination tools without exposing the activity.

### Join flow
- Public activities: direct join (creates `accepted` participation).
- Approval activities: request → creator accepts/refuses → notification.
- Concurrent join race condition protected by Postgres advisory locks.
- Rejoin after withdrawal allowed (once); removal by creator is final.

### Wall (group chat per activity)
- Only accepted participants read/write.
- 1 message per minute rate limit.
- Realtime via Supabase.
- Soft delete with edit history preservation.

### Private messaging
- 1:1 conversations, lazy-created on first message.
- Ordered-pair uniqueness (no duplicate conversations).
- Bidirectional block enforcement (both directions prevented from sending).
- Push-only notifications (no in-app notification for every message — would spam).
- Cursor pagination, Realtime updates.

### Profiles
- Own profile edit: display name, bio, sports, levels per sport, avatar.
- Public profile view: aggregate stats (completed activities, reliability score, sports practiced, member since), reputation badges, trophy badges.
- Block / unblock / report buttons.
- Avatar upload with EXIF stripping + magic-byte validation + 5MB cap.

### Trust model
A composite system:
- **Reliability score**: Bayesian with PRIOR=3, recalculated on every `confirmed_present` flip. Stored in `users.reliability_score` (private). Public exposure as `reliability_tier` (excellent ≥ 90, good ≥ 75, fair ≥ 50, poor < 50). Displayed as ring + pill on profile (% private to self, tier label public).
- **Reputation badges** (8 types peer-voted): trustworthy / great_leader / good_vibes / punctual + 4 negatives (level_overestimated / difficult_attitude / unreliable_field / aggressive). Co-participants vote in the peer-review window (end+15min..end+24h). Thresholds: 5+ to show positive, 15+ to flag negative.
- **Progression badges** (mig 00135): tiered system across 3 categories (joined, created, sport-per-key) × 5 tiers (t1@5 / t2@10 / t3@20 / t4@50 / t5@75). Auto-attributed by trigger on activity completion. Notif `badge_unlocked` fires at each level-up. Display: icon-only chips with count overlay, tier pill below; tap → ladder modal.
- **Sport-level endorsements** (mig 00097): peers can confirm or contest the level a user announced for a given sport.

### Presence verification — V3 (mig 00141..00149)
Multi-path with offline graceful degradation. Voir `docs/DAY_OF_ACTIVITY.md` pour le détail complet.

**Validation windows:**
- Geo registration (OS geofence): T-2h → T+15min
- Geo validation gate: T-15min → T+15min, distance ≤ 150m to start / meeting / end / route polyline
- QR validation: T-15min → end + 3h
- Offline replay arrival: ≤ end + 3h
- Peer review: end + 15min → end + 24h

**Paths (in fallback order):**
1. Background geofence task wakes app on Enter event → "Présence détectée" → RPC → "Présence confirmée" (one OS slot, replaces in place)
2. Foreground watcher (30s poll) auto-confirms when in zone (no local notif, in-app state covers)
3. App-open initial-state check (fires when user is already inside on app foreground)
4. Activity-detail page poll (focused on the active activity)
5. Manual "I'm here" button
6. QR scan (creator displays token, participant scans)
7. Offline replay (cache while no network, drain on reconnect)
8. Peer review (threshold 1 in 2-participant, threshold 2 in 3+ ; voter must be confirmed_present themselves except for 2-participant creator-direct case)

Per-activity `requires_presence` toggle (default TRUE). Casual organisers can disable for gym climbing, coffee, slackline, etc.

**Notification spine** (mig 00148):
- T-2h: `presence_pre_warning`
- T0: `presence_validate_now` (if not yet confirmed)
- T0: `qr_create_reminder` (creator only)
- T+duration/2: `presence_validate_warning` (escalation: "tu seras enregistré comme absent")
- Validation: `presence_confirmed` push
- end: `rate_participants` (in-app)
- end+22h: `peer_review_closing` (push to non-voters)
All `presence_*` types share a `collapse_id = 'presence-{activity_id}'` — single OS slot per activity.

### Cancellation flow
- **Participant leaves**: `leave_activity(reason?)`. If `< 12h` before start AND `requires_presence=true`, counts as late cancel for reliability calculation.
- **Creator cancels whole activity**: requires non-empty reason, notifies all accepted participants.
- **Creator can waive** a participant's late-cancel penalty if they provide context.

### Activity alerts (Premium gated, de-facto free due to auto-premium)
- Create alert with sport + level + location + radius (slider up to 100km).
- Matching public/approval activities trigger a push notification.
- Max 10 alerts/user.

### Reports + admin moderation
- Report user, activity, wall message, or private message with reason.
- Admin-only screen to review pending reports, dismiss or action, optional suspension of target user.
- Rate-limited (10 reports/hour).

### Push notifications
- Expo Push via a Supabase Edge Function (`send-push`) with shared-secret authentication.
- Multi-device aware: `push_tokens` table (mig 00121) keyed on `(user_id, device_id)` ; device_id persisted in SecureStore.
- Routing per type in the `push_notification_to_device` trigger (mig 00148): collapse_id by activity, in-app-only for some types (rate_participants, request_refused, participant_left_late), pluralization (×N) on the presence slot.
- Events covered: join request, request accepted/refused, participant joined (collapsed), activity cancelled (gated push if <48h away), activity updated (gated to logistics changes), wall mention, message received, alert match (capped 3/day), rate-participants prompt, peer_review_closing, badge_unlocked, presence_* family, seat_request, contact_request, etc.
- Content designed to reveal nothing sensitive in the push preview ; sanitization via `sanitize_notif_text` (HTML strip + control char + 200 char clip).

### Onboarding
- IP-based country detection for initial map center (no permission needed).
- Tutorial tooltips on first login.
- Transient demo activity so the map isn't empty for first-time users.

### Web companion
- Next.js landing page at `getjunto.app` (Vercel).
- OAuth / email confirmation callback (`/auth/callback`).
- Reset-password bridge (`/auth/reset-password`) — extracts token from URL (query or hash), redirects to `junto://reset-password` deep link.
- Share previews for activities (`/activity/[id]`) and invite tokens (`/invite/[token]`).
- Legal pages (FR + EN) — terms, privacy.
- App Links verification (`/.well-known/assetlinks.json`).

### Observability
- Sentry wired in `src/lib/sentry.ts`, auto-consent on preview channel only (production awaits explicit consent UI).
- Heavy scrubbing in `beforeSend`: `lat`, `lng`, `latitude`, `longitude`, `email`, `phone`, `body`, tokens, etc. all auto-redacted.
- Helper `trace(category, message, data)` for diagnostic breadcrumbs ; no-op in dev.
- Categories used: `presence.geofence` (Enter event, RPC outcome, enqueue), `presence.watcher` (in-zone detection, accuracy reject), `presence.offline` (replay outcomes).
- Max 50 events per session ; `tracesSampleRate: 0` (no perf monitoring).

### Settings drawer redesign
- Pencil icon next to display name signals editable.
- "Ma position" toggle — gates background location + geofencing.
- Notif preferences expandable section, granular per type.
- Theme as segmented pill (auto / clair / sombre) — single rounded pill with three sections.
- Map style block dropped from drawer (already on the map screen).
- Settings drawer + login + reset-password + profile-hero share the topo SVG visual signature.

---

## 5. Deliberate gaps and temporary hacks

These are **known** and **intentional** — don't propose fixing them without understanding why.

### Phone verification: disabled
Migration [`00050_disable_phone_verification_check.sql`](https://github.com/Torof/Junto/tree/main/supabase/migrations) removed the `phone_verified` check from `create_activity`. Reason: Twilio SMS integration adds complexity and cost; for a small dogfooding circle it's pointless friction. Restore before wider launch.

### Auto-Premium for new users: temporary
Migration `00051_auto_premium_new_users.sql` promotes every new user to Premium. Reason: Stripe isn't integrated yet, and we want testers to exercise Premium features. Revert when Stripe payment flow ships.

### Premium gates still in code
The code still checks tier for private-link visibility and alert creation. All users being Premium means these checks are no-ops. That's fine — when Stripe lands, flipping `00051` back to free-by-default re-enables the gates automatically.

### Stripe: not implemented
No `stripe_customer_id`, no `subscription_status` column, no payment flow, no webhook handler. Deliberately deferred. The premise: monetization without users is meaningless. Ship, get traction, then integrate Stripe.

### Pro verification: schema only
`is_pro_verified` and `pro_verified_at` columns exist. No document upload UI, no admin review screen, no Pro badge UI. Deferred for the same reason as Stripe.

### Conversation per-user read tracking: TODO
[`src/services/conversation-service.ts`](https://github.com/Torof/Junto/blob/main/src/services/conversation-service.ts) has a TODO. Current state: `conversations.last_message_at` exists but no `last_read_at` per user, so the unread badge on the Messagerie tab is approximate. Half-day fix; not done because the testers haven't complained.

### E2E tests: none
No Detox, no Maestro. Manual testing only. Planned for post-Sentry, pre-launch.

### Analytics: none
No PostHog, no Mixpanel. Can't answer "how many signups convert to first activity creation" today. Planned right after Sentry validates.

### Transport coordination: spec'd but not shipped
Feature for drivers/passengers/lift-needed coordination on asymmetric activities (paragliding, one-way hikes). Fully specified in [`docs/DECISIONS.md`](https://github.com/Torof/Junto/blob/main/docs/DECISIONS.md) (entry 2026-04-15), shipping deferred until testers explicitly ask.

### Not pursuing now, mentioned in VISION.md
- **v2 spots layer** — permanent location pages (canyons, climbing sites) alongside event pins. Huge scope, depends on partnership strategy with established topo communities (camptocamp, descentecanyon, etc.) rather than competing. See [`docs/VISION.md`](https://github.com/Torof/Junto/blob/main/docs/VISION.md).
- **iOS** — will happen, currently Android-only.
- **Friend graph** — Junto is people-to-people but not friend-based. No plans to add.
- **GPS spoofing detection** — mentioned in backlog as post-launch.
- **Certificate pinning** — same.

---

## 6. Architecture at a glance

**Stack** (see [`docs/TECH_STACK.md`](https://github.com/Torof/Junto/blob/main/docs/TECH_STACK.md) for full details):
- React Native + Expo SDK 54 + TypeScript (strict, no `any`).
- Expo Router (file-based routing, auto deep linking, typed routes).
- TanStack Query for server state, Zustand for UI state only.
- Zod for type derivation (runtime validation lives in DB SECURITY DEFINER functions ; React Hook Form was dropped — forms use inline state).
- Supabase: Postgres 15 + PostGIS + Auth + Realtime + Storage + Edge Functions. Hosted, not local.
- Mapbox Outdoors + Google Places.
- TaskManager + AsyncStorage + NetInfo for background geofencing + offline replay cache.
- Sentry (preview-only auto-consent) for breadcrumbs + error tracking.
- day.js, expo-image, react-native-i18next (FR + EN, pluralization via `_one`/`_other` suffixes).

**Security model** (see [`docs/SECURITY.md`](https://github.com/Torof/Junto/blob/main/docs/SECURITY.md), ~1000 lines, comprehensive):
- All writes go through SECURITY DEFINER Postgres functions. No direct client INSERT/UPDATE/DELETE on critical tables.
- RLS on every table, `FORCE ROW LEVEL SECURITY`.
- Authorization chains documented per function. No RLS backup — if the function forgets a check, it's a vulnerability.
- Whitelist triggers on `users` and `activities`: privileged columns forced to `OLD` values on UPDATE, only explicitly allowed fields can change.
- Generic error messages only ("Operation not permitted"), never implementation details.
- 4 explicit security audit passes baked into migrations (`00044`, `00045`, `00046`, `00066`).

**Data flow pattern:**
- Client → Service (`src/services/*`) → RPC call → Postgres function → RLS → table.
- Queries: Client → Service → view (`public_profiles`, `activities_with_coords`, `my_activities`, `my_joined_activities`) — never the raw `users` table.
- Realtime: Client subscribes to `public.*` channels; RLS applies to subscription filtering.

**State split:**
- **Server state** (activities, messages, profiles): TanStack Query.
- **UI state** (form wizard progress, map viewport): Zustand.
- **Never mixed** — TanStack is the single source of truth for server data; Zustand never caches server data.

---

## 7. Repo tour — where to look

Main code:
- [`app/`](https://github.com/Torof/Junto/tree/main/app) — Expo Router screens (file-based routing). Split into `(auth)` and `(visitor)` route groups.
- [`src/components/`](https://github.com/Torof/Junto/tree/main/src/components) — ~30 components.
- [`src/services/`](https://github.com/Torof/Junto/tree/main/src/services) — one service per domain (activity-service, participation-service, etc.).
- [`src/hooks/`](https://github.com/Torof/Junto/tree/main/src/hooks) — auth, geolocation, network, push notifications.
- [`src/store/`](https://github.com/Torof/Junto/tree/main/src/store) — Zustand stores (UI state only).
- [`src/i18n/`](https://github.com/Torof/Junto/tree/main/src/i18n) — FR + EN translations.
- [`src/constants/theme.ts`](https://github.com/Torof/Junto/blob/main/src/constants/theme.ts) — colors, spacing, typography. Never hardcode.

Database:
- [`supabase/migrations/`](https://github.com/Torof/Junto/tree/main/supabase/migrations) — 149 numbered migrations.
- [`supabase/functions/send-push/`](https://github.com/Torof/Junto/tree/main/supabase/functions/send-push) — Edge Function for Expo Push.
- `supabase/functions/delete-user/` — Edge Function for account deletion (uses service_role).

Web:
- [`web/`](https://github.com/Torof/Junto/tree/main/web) — Next.js landing + share previews + OAuth callback.

Docs (all refreshed 2026-04-28):
- [`CLAUDE.md`](https://github.com/Torof/Junto/blob/main/CLAUDE.md) — working rules + checklists for new tables/functions/features.
- [`docs/PRODUCT.md`](https://github.com/Torof/Junto/blob/main/docs/PRODUCT.md) — product definition (French).
- [`docs/SECURITY.md`](https://github.com/Torof/Junto/blob/main/docs/SECURITY.md) — the security bible (French).
- [`docs/TECH_STACK.md`](https://github.com/Torof/Junto/blob/main/docs/TECH_STACK.md) — stack details.
- [`docs/DECISIONS.md`](https://github.com/Torof/Junto/blob/main/docs/DECISIONS.md) — why things are the way they are (append-only).
- [`docs/VISION.md`](https://github.com/Torof/Junto/blob/main/docs/VISION.md) — long-term direction.
- [`docs/UX_UI.md`](https://github.com/Torof/Junto/blob/main/docs/UX_UI.md) — design system.
- [`docs/WORKING_MODE.md`](https://github.com/Torof/Junto/blob/main/docs/WORKING_MODE.md) — conventions (commits, branching, OTA channels).
- [`docs/ACTIVITY_MANAGEMENT.md`](https://github.com/Torof/Junto/blob/main/docs/ACTIVITY_MANAGEMENT.md) + [`DAY_OF_ACTIVITY.md`](https://github.com/Torof/Junto/blob/main/docs/DAY_OF_ACTIVITY.md) + [`REPUTATION_BADGES.md`](https://github.com/Torof/Junto/blob/main/docs/REPUTATION_BADGES.md) — feature-specific specs.
- [`docs/BACKLOG.md`](https://github.com/Torof/Junto/blob/main/docs/BACKLOG.md) — current open items (refreshed 2026-04-26).
- [`docs/sprint-discovery.md`](https://github.com/Torof/Junto/blob/main/docs/sprint-discovery.md) — Discovery feature spec (Phase B-E pending).

---

## 8. Open product questions

Real ones — worth discussing, not decided.

1. **Should presence verification be mandatory post-launch?** Today it's opt-out per activity. Making it mandatory strengthens trust data but friction-costs casual outings. Middle path: mandatory for activities with 3+ participants, optional for 1:1.
2. **Are reputation badge thresholds right?** 5+ positive to show, 15+ negative to flag. Completely guessed. Revisit after 100 activities of real data.
3. **Is the 12h late-cancel window right?** Some sports need more warning (2-day trips need 48h+). Per-activity threshold? Per-sport default?
4. **Is 1 wall message per minute too restrictive?** "Hey I'm running 10 minutes late" is a legitimate burst. Allow bursts of 3 then cool down?
5. **How do we seed activity density pre-launch?** A map with 3 pins looks dead. Options: hand-curated seed activities in a few target regions, partnerships with existing clubs, influencer-driven launch in one city at a time. Not solved.
6. **iOS before or after Stripe?** iOS without monetization = audience expansion. Stripe without iOS = revenue on a limited platform. No right answer.
7. **Should the free tier stay at 4 activities/month, or tighten to 1-2?** Higher conversion rates but more churn from frustrated free users.
8. **Does the "spots" v2 idea (permanent location pages) belong in Junto, or as a partnership integration?** See [`docs/VISION.md`](https://github.com/Torof/Junto/blob/main/docs/VISION.md). Scott leans partnership.
9. **How do we handle a no-show by the creator?** Currently a participant without their creator has no recourse. Auto-cancel the activity 30min after start if creator hasn't checked in?
10. **Should private messaging survive past MVP?** It was deprioritized, yet shipped. If usage stays low, removing it simplifies the app; if it grows, it becomes a retention lever worth investing in.
11. **Transport coordination (spec'd in DECISIONS.md 2026-04-15): ship pre-emptively or on signal?** Current plan: on signal. Could be wrong if the feature is the thing that unlocks one-way activity growth.
12. **How do we detect and discourage activities that aren't real sports meetups?** Someone posting a climbing session as a dating hook, or a guided tour disguised as casual. Reports work reactively; prevention is open.
13. **Does per-user "last_read_at" on conversations belong in a dedicated table, or as columns on `conversations`?** Small design decision, both work.
14. **What's the first signal that we've hit product-market fit?** Not measured. Candidate signals: % of users who create a second activity within 14 days; average participants per activity; % of activities that happen (aren't cancelled or no-show'd).
15. **Do we need a safety tips / code of conduct screen before first activity creation?** Legal softens liability; UX-wise adds friction. Current: only ToS.

---

## 9. Decided and not worth re-opening

Not because they're sacred — because they've been chewed on and reopening them is expensive.

- **Android first, iOS later.** Resource question, not strategy.
- **Mapbox over Google Maps.** Outdoor visibility beats road detail.
- **Supabase over Firebase.** Postgres + RLS fit the security model; Firebase's NoSQL + rules language would require reinventing half the access layer.
- **Random display name on signup.** Reduces friction; users fix it later.
- **FR + EN only at launch.** Scott is French; target market is primarily French-speaking Europe; English covers most other early testers.
- **No ads, ever.** Monetization is subscription-based (Premium/Pro). See [`docs/PRODUCT.md`](https://github.com/Torof/Junto/blob/main/docs/PRODUCT.md).
- **Pro payments stay outside the app.** Junto is a showcase for Pros, not a payment intermediary — avoids payment regulation complexity.
- **One-person dev team for now.** Scott codes with AI assistance (Claude). Not hiring until traction.

---

## 10. Working mode

Scott codes with Claude as his pair/collaborator. Flow:
1. Scott describes what he wants.
2. Claude proposes an approach (architecture + security + files touched) in prose.
3. Scott validates explicitly before any code is written.
4. Claude implements.
5. Scott tests on his preview build and iterates.
6. Commit with conventional commits (`feat(scope):`, `fix(scope):`, etc.), in English.
7. Deploy: `eas update --branch preview` for JS-only changes, `eas build --profile preview --platform android` for native changes.

Critical constraint for AI collaborators: **never code without Scott's explicit approval**. Propose first. This is non-negotiable — it's in [`CLAUDE.md`](https://github.com/Torof/Junto/blob/main/CLAUDE.md) line 1.

Language for responses: English unless Scott writes in French.

---

## How to use this document

If you're an AI session being handed this briefing, read it top to bottom once. Then:
- For product questions → consult sections 3, 4, 8, 9.
- For technical questions → section 6, then go read the file in the repo.
- For "why did we do X" → section 5 + [`docs/DECISIONS.md`](https://github.com/Torof/Junto/blob/main/docs/DECISIONS.md).
- For "what's not done" → section 5.
- If the question falls outside what's here: check the repo (it's public), or ask Scott.

If something in this document contradicts current code, the code wins. This is a point-in-time snapshot; features evolve.
