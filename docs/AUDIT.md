# Pre-launch security audit — 2026-05-16

Six parallel research passes against the codebase as of commit `17b9125`:
1. RPC auth chains (SECURITY DEFINER functions)
2. RLS policies on every table
3. Privileged-column whitelist triggers
4. Storage buckets + Edge Functions
5. Client-side surface (CLAUDE.md "Critical Rules")
6. Recent migrations (00214..00233) sanity

Findings below are grouped by severity. Each row has a file:line ref and a one-line fix. Sign off / re-triage row-by-row, then ship migrations + client changes.

---

## Critical

### ✅ C1 — `delete_own_account` leaves `auth.users` orphaned
**Shipped** (commit 64515ed). New `supabase/functions/delete-account` edge fn verifies the caller's JWT, calls the RPC as them, then `admin.deleteUser()` with service_role. Client wired at `settings-drawer.tsx:321` to invoke the function instead of the RPC directly.

### ✅ C2 — `wall_messages` SELECT policy doesn't filter suspended authors
**Shipped** (migration 00234, commit 64515ed). Suspended users' wall posts now hard-hide from every participant. Public surface, hard-hide stance.

### ⊘ C3 — `private_messages` SELECT policy doesn't filter suspended senders
**Decision: keep current behaviour** (read-only ghost). DMs are 1:1 private — the counterparty already saw the messages. Suspending a user blocks them from sending new DMs (existing suspension check in `send_private_message`), but past content stays visible to the recipient.

### ⊘ C4 — `conversations` SELECT policy exposes suspended counterparties
**Decision: keep current behaviour** (same rationale as C3). Conversation rows remain visible to the counterparty so the thread stays readable.

---

## High

### ✅ H1 — Logistics RPCs reject submissions at the activity-start boundary
**Shipped** (migration 00235, commit 927db39). Switched the six 00233 functions to `starts_at > NOW() - INTERVAL '15 seconds'`.

### ⊘ H2 — `seat_requests.status` CHECK missing `'expired'`
**Dropped (stale finding).** Migration 00142 already added `'expired'` to the CHECK; the audit agent compared against the original 00076 CHECK and missed the modification.

### ✅ H3 — Raw error messages leak to user alerts
**Shipped** (commit 927db39). Replaced `err.message` user-facing alerts with `getFriendlyError` in `activity-detail.tsx`, `conversation/[id].tsx`, `create/step2.tsx`, and `peer-review/[id].tsx`. `GpxParseError` messages kept (own parser, diagnostic, helps the user fix the file).

### ✅ H4 — Type-cast bypass in `conversation-service.ts`
**Shipped** (commit 927db39). Dropped all `as 'users'` / `as unknown` casts — generated Supabase types already cover the conversations table and all four RPCs. Type safety now restored across getAll / getPendingReceived / sendContactRequest / acceptRequest / declineRequest / getConversationStateWith / hideConversation.

---

## Medium

### ✅ M1 — `give_reputation_badge` missing bidirectional block guard
**Shipped** (migration 00236). Added the standard bidirectional `blocked_users` guard right after the self-vote check.

### ✅ M2 — `get_user_reputation` + `get_user_trophies` skip auth/suspension checks
**Shipped** (migration 00236). Both now follow the documented auth-chain prelude (`auth.uid()` + suspension), matching the 00226 pattern.

### ✅ M3 — Sentry scrubber misses `display_name`
**Shipped** (commit below). Added `display_name`, `name`, `full_name` to `SENSITIVE_KEYS`.

### ✅ M4 — `trace()` helper doesn't scrub `data` before adding breadcrumb
**Shipped** (commit below). `trace()` now scrubs `data` inline before `Sentry.addBreadcrumb`.

### ✅ M5 — Push notification payload forwards raw `NEW.data` jsonb
**Shipped** (migration 00236). `push_notification_to_device` now intersects `NEW.data` with an allow-list (`activity_id`, `conversation_id`, `seat_request_id`, `driver_id`, `requester_id`, `from_user_id`) before forwarding. `type` is always added. Everything else stays in the `notifications` row for in-app rendering.

### ✅ M6 — Avatar upload trusts client-reported MIME
**Shipped** (commit below). After `manipulateAsync` (which always re-encodes as JPEG), the base64 buffer is now verified to start with `/9j/` (JPEG SOI). Defence-in-depth against future encoder changes / any path that skips manipulation.

### ⊘ M7 — Reads referencing logistics state aren't time-gated
**Decision: not actionable.** Post-start reads are intentional: presence validation, peer-review windows, and end-of-activity rituals all need to read transport/seat/gear state *after* start. Writes are correctly locked by 00233/00235 — reads stay open by design.

### ⊘ M8 — Documentation drift in 00232 comment on directional block filter
**Decision: defer.** Pure doc nit; the runtime behaviour is correct and matches SECURITY.md. Will address as part of a docs-only sweep, not as a security fix.

---

## Notes / clean slices

- **Privileged-column whitelist triggers**: clean. Users / activities / notifications / participations all properly protected (00066 / 00212 / 00216 + intentional no-trigger on participations).
- **Service-role key in client**: clean — zero matches.
- **`.select('*')` in client**: clean.
- **`.from('users')` direct usage**: clean — all joins go through `public_profiles`.
- **URL auto-linking in UGC**: clean.
- **Hardcoded secrets / URLs**: clean.
- **Console logging in src/app**: clean.
- **Realtime channel filtering**: clean — all channels per-activity / per-user.
- **Initial RPC audit finding "00217 missing `starts_at > NOW()`"**: STALE — 00233 republished `accept_seat_request` with the gate. Dropped from this list.

---

## Suggested fix order

1. **C1** (delete-account edge function) — highest blast-radius for users and auditors.
2. **C2–C4** + **M3/M4** — one migration + one client diff, all touching the "suspended user data leak" theme.
3. **H1** (grace period in logistics lock) — tiny migration, prevents user-visible bugs at activity start.
4. **H3/H4** — client cleanup, ship as one PR.
5. **M1/M2/M5/M6/M7** — defence-in-depth pass; bundle the reputation auth chain + block-guard fixes as one migration.
6. **H2/M8** — schema reconciliation + doc nit, low urgency.
