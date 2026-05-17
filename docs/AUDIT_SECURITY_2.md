# Security audit — round 2 — 2026-05-16

Six fresh parallel passes covering dimensions the [first audit](AUDIT.md) didn't reach: race conditions, realtime channel auth, rate limiting, edge-function deep-dive, deep-link / auth-flow enforcement, input-validation surface. Plus an `npm audit` for dependency CVEs.

**Status legend:** ⏳ open · ⊘ dropped/over-flagged · ✅ shipped

Severities reflect *my* triage of the agent findings — some agent "Critical" calls have been downgraded after looking at the actual exploitability.

---

## Critical

### ✅ C1 — `queryClient` not cleared on logout (cross-user data bleed)
**Shipped** (commit 6b63e1b). `use-auth` now clears the query cache on every `SIGNED_OUT` / `USER_UPDATED` / null-session event.
On a shared device, signing out and signing in as a different user shows the previous user's cached activities, messages, notifications and profile until each query refetches. [settings-drawer.tsx:152-155](../src/components/settings-drawer.tsx#L152-L155), [use-auth.ts onAuthStateChange:68-82](../src/hooks/use-auth.ts#L68-L82), plus the suspended / delete-account exit paths.
**Fix:** Centralize signOut behind a wrapper that calls `queryClient.clear()` first. Also call it inside `onAuthStateChange` on `SIGNED_OUT` events.

### ✅ C2 — Deep-link bypass into `/(auth)/activity/[id]` before auth resolves
**Shipped** (commit 6b63e1b). Per-screen auth gate added at the top of the screen — returns `<Redirect href="/(visitor)/login">` (or `/suspended`) before any query fires.

### ⊘ C3 — `confirm_presence_via_token` creator auto-flip
**Dropped (over-flagged).** Re-reading 00167:187-199 shows the creator flip is already race-safe via `UPDATE ... WHERE confirmed_present IS NULL` + `GET DIAGNOSTICS ROW_COUNT > 0` gating the notification. Only one concurrent caller's UPDATE actually flips; others see zero ROW_COUNT and don't double-notify. No fix needed.

### ✅ C4 — `peer_validate_presence` vote count race
**Shipped** (migration 00237). Added `pg_advisory_xact_lock(hashtext('peer_validate:' || p_activity_id::text || ':' || p_voted_id::text))` at function entry to serialize concurrent voters on the same target.

### ✅ C5 — `request_seat` rate limit
**Shipped** (migration 00237). 5 requests / 5 minutes per requester, advisory-locked.

### ✅ C6 — `give_reputation_badge` rate limit
**Shipped** (migration 00237). 20 votes / 24h per voter, advisory-locked.

---

## High

### ✅ H1 — `accept_seat_request` doesn't check `ROW_COUNT` on requester transport clear
**Shipped** (migration 00238). Function now raises if the requester left between the earlier SELECT and the clear UPDATE.

### ✅ H2 — `join_activity` capacity check / INSERT race
**Shipped** (migration 00238). Re-checks capacity immediately before INSERT/UPDATE with the activity row still locked.

### ✅ H3 — `delete-account` edge function leaks `user_id` in error response
**Shipped** (deployed). Error responses no longer echo `user_id`; operator log retains it via `console.warn`.

### ✅ H4 — `send-push` console-logs raw error messages
**Shipped** (deployed). Replaced `delErr.message` / `e` with stable labels + counts.

### ✅ H5 — HTML stripping on four trim-only RPC fields
**Shipped** (migration 00238). `set_participation_transport.transport_from_name`, `request_seat.pickup_from`, `set_activity_gear` gear_name, `create_report.reason` all now go through `regexp_replace(..., '<[^>]*>', '', 'g')`.

### ✅ H6 — column-level CHECK on `conversations.request_message`
**Shipped** (migration 00238). Added `CHECK (char_length(request_message) BETWEEN 1 AND 500)`.

### ✅ H7 — `set_activity_gear` accepts an unbounded JSONB array
**Shipped** (migration 00238). Caps at 50 items.

### ⊘ H8 — `npm audit` CVEs
**Deferred.** Both `@xmldom/xmldom` and `fast-uri` are transitive build-only deps via Expo (`expo-updates → plist`, `expo-dev-client → ajv`). Not in runtime path. Wait for Expo SDK bump.

---

## Medium

### ✅ M1 — Realtime: `tabs-badges` global subscription for notifications + private_messages
**Shipped** (commit 2f82a61). Channel name is now per-user (`tabs-badges:{userId}`) and both subscriptions filter on `user_id=eq.{userId}` / `receiver_id=eq.{userId}`.

### ⊘ M2 — Realtime: `activities-nearby` global subscription
**Acceptable** (lower stakes — activity existence is public info anyway). Would need a per-bbox filter that postgres_changes doesn't expose natively.

### ✅ M3 — Auth-flow: `checkUserStatus` is fire-and-forget
**Shipped** (commit 2f82a61). `use-auth` now `await`s the status check before setting `isLoading = false`. The 8s safety timeout still unblocks if the RPC hangs.

### ✅ M4 — `set_date_of_birth` / `accept_tos` lack advisory locks
**Shipped** (migration 00239). Per-user advisory lock at function entry.

### ✅ M5 — `send_contact_request` pending-cap is not time-windowed
**Shipped** (migration 00239). 5 / 24h daily cap added on top of the existing 10-pending bound, behind the same advisory lock.

### ✅ M6 — Suspended user can briefly view `(auth)` content via back button
**Shipped** (commit 2f82a61). Second-layer guard inside `(auth)/_layout.tsx` returns `<Redirect href="/(visitor)/suspended" />` before any child screen mounts.

### ⊘ M7 — `npm audit`: `postcss` moderate XSS in stringify
**Deferred** (same as H8). Build-time dep; not runtime-exploitable. Awaits Expo SDK bump.

---

## Low / dropped / over-flagged

- **send-push deployment flag** — the agent flagged "no enforcement that `--no-verify-jwt` was used". Not a code concern; can't be addressed in source. Note in deploy docs only.
- **`constantTimeEqual` length leak** — agent's "Medium". Secret is fixed-length; length leakage is harmless. Drop.
- **`messagerie-incoming:${currentUserId}` ID substitution** — agent flagged the *possibility* of someone refactoring `currentUserId` from a routing param. Current code is correct; not actionable until/unless the refactor happens.
- **reset-password while authenticated** — agent flagged as High but it's the documented recovery flow. Intentional.
- **`reports.admin_note` unbound** — agent rated Critical. Field is moderator-internal (filled by ops, not users). No user input path. Drop.
- **GPX parser MAX_POINTS = 10000** — agent rated Low, "could be 5000". 10k is fine for a real GPX file. Drop.
- **`delete_own_account` no rate limit** — design decision (one-shot delete with confirmation chain in the UI). Documented.
- **`send_private_message` no rate limit** — explicitly removed in [00185](../supabase/migrations/00185_drop_private_message_rate_limit.sql) for product reasons (block + report are the brakes). Documented.

---

## Suggested fix order

1. **C1** — `queryClient.clear()` on logout. One-line behavioural fix, huge impact. Ship first.
2. **C2** — auth gate inside `activity/[id]` (or any other deep-linkable `(auth)` screen). Audit + add early `<Redirect>`.
3. **C5 + C6** — rate limits on `request_seat` and `give_reputation_badge`. Bundle into one migration with the H5/H6/H7 input-validation fixes.
4. **C3 + C4** — `FOR UPDATE` on creator presence flip + advisory lock on peer-vote count. Concurrency hardening, same migration.
5. **H1 + H2** — `accept_seat_request` ROW_COUNT, `join_activity` re-check capacity. Quick adds.
6. **H3 + H4** — drop `user_id` from delete-account error; scrub send-push logs.
7. **H5 (HTML stripping sweep)** — one migration patching the four trim-only RPCs.
8. **H7** — JSONB array bound on `set_activity_gear`. Same migration as H5.
9. **M1** — filter `tabs-badges` subscriptions on user_id.
10. **M3 + M6** — auth-flow tightening: await `checkUserStatus`, suspended guard in `(auth)/_layout`.
11. Everything else as time permits.
