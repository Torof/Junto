# Security audit — round 2 — 2026-05-16

Six fresh parallel passes covering dimensions the [first audit](AUDIT.md) didn't reach: race conditions, realtime channel auth, rate limiting, edge-function deep-dive, deep-link / auth-flow enforcement, input-validation surface. Plus an `npm audit` for dependency CVEs.

**Status legend:** ⏳ open · ⊘ dropped/over-flagged · ✅ shipped

Severities reflect *my* triage of the agent findings — some agent "Critical" calls have been downgraded after looking at the actual exploitability.

---

## Critical

### C1 — `queryClient` not cleared on logout (cross-user data bleed)
On a shared device, signing out and signing in as a different user shows the previous user's cached activities, messages, notifications and profile until each query refetches. [settings-drawer.tsx:152-155](../src/components/settings-drawer.tsx#L152-L155), [use-auth.ts onAuthStateChange:68-82](../src/hooks/use-auth.ts#L68-L82), plus the suspended / delete-account exit paths.
**Fix:** Centralize signOut behind a wrapper that calls `queryClient.clear()` first. Also call it inside `onAuthStateChange` on `SIGNED_OUT` events.

### C2 — Deep-link bypass into `/(auth)/activity/[id]` before auth resolves
Cold-launching `juntoapp://activity/abc123` while unauthenticated briefly renders the protected screen before AuthGate detects the empty session and redirects. The activity screen itself does no auth check. [_layout.tsx:56-59](../app/_layout.tsx#L56-L59), [activity/[id].tsx:28-56](../app/(auth)/activity/[id].tsx#L28-L56).
**Fix:** Add an early `if (!isAuthenticated) return <Redirect href="/(visitor)/login" />` inside the screen, OR guarantee the AuthGate splash overlay is on screen until auth state resolves (extend the 8s timeout, gate `isReady` on auth-resolved).

### C3 — `confirm_presence_via_token` creator auto-flip is not row-locked
[00163_confirm_presence_idempotent.sql:173-179](../supabase/migrations/00163_confirm_presence_idempotent.sql#L173-L179) — auto-confirms the creator's participation with `UPDATE ... WHERE confirmed_present IS NULL` without a prior `FOR UPDATE` on that row. Concurrent peer-validation / QR / geofence calls can interleave and produce stale-read state.
**Fix:** Acquire `FOR UPDATE` on the creator's participation row before the conditional UPDATE, or fold the creator flip into the initial participation SELECT.

### C4 — `peer_validate_presence` vote count race
[00140_peer_validate_drop_creator_privilege.sql:116-122](../supabase/migrations/00140_peer_validate_drop_creator_privilege.sql#L116-L122) — INSERTs the vote, then counts votes for the same target, then conditionally flips presence. Two simultaneous voters can both see "count = threshold" and race the flip UPDATE. Only one succeeds because of the `confirmed_present IS NULL` predicate, but the threshold semantics get fuzzy under load.
**Fix:** Wrap insert + count + flip in `pg_advisory_xact_lock(hashtext('peer_validate:' || p_activity_id::text || ':' || p_voted_id::text))`.

### C5 — `request_seat` has no rate limit
[00235:147](../supabase/migrations/00235_logistics_lock_grace_period.sql#L147) — a malicious user can spam every driver of every activity with seat requests, generating unbounded notifications + DMs. Per-driver/per-requester window cap is missing.
**Fix:** Advisory lock + count-in-window (e.g., 5 / 5min / requester) before the INSERT.

### C6 — `give_reputation_badge` has no rate limit
[00159_dead_artifact_sweep.sql:212-291](../supabase/migrations/00159_dead_artifact_sweep.sql#L212-L291) — UNIQUE constraint prevents same-badge duplicates per (voter, voted, activity), but a malicious voter can hit every completed activity at scale to dump negative badges.
**Fix:** Advisory lock + 20 / day / voter cap.

---

## High

### H1 — `accept_seat_request` doesn't check `ROW_COUNT` on requester transport clear
[00235:359-365](../supabase/migrations/00235_logistics_lock_grace_period.sql#L359-L365) — if the requester left the activity between the initial SELECT and the transport-clear UPDATE, the UPDATE silently no-ops and the function returns success. Soft inconsistency.
**Fix:** `GET DIAGNOSTICS v_count = ROW_COUNT; IF v_count = 0 THEN RAISE ...` after the requester transport UPDATE.

### H2 — `join_activity` capacity check / INSERT race
[00117_notif_overhaul.sql:314-352](../supabase/migrations/00117_notif_overhaul.sql#L314-L352) — `FOR UPDATE` on the activity row serializes joins but doesn't strictly prevent count > max_participants under concurrent bursts (the count happens once, the INSERT happens later). Soft constraint breach possible.
**Fix:** Re-check capacity immediately before INSERT, with the activity row still locked; raise if exceeded.

### H3 — `delete-account` edge function leaks `user_id` in error response
[supabase/functions/delete-account/index.ts:65](../supabase/functions/delete-account/index.ts#L65) — error JSON includes the caller's `user_id` if `auth.admin.deleteUser` fails. Caller already knows their ID, but reflecting it back is a habit worth breaking.
**Fix:** Drop `user_id` from the response body; log it server-side via Sentry/console for operator debugging.

### H4 — `send-push` console-logs raw error messages
[send-push/index.ts:151, :155](../supabase/functions/send-push/index.ts#L151) — dead-token cleanup logs `delErr.message` and the generic Expo response `e` verbatim. Function logs may carry stack traces / tokens / internal paths.
**Fix:** Scrub or replace with generic messages; or pipe through Sentry's redaction layer.

### H5 — User-content fields with CHECK constraint but no HTML strip
Stored XSS-safe only when the renderer escapes — but if anything renders `dangerouslySetInnerHTML` (none today, but the safety net is missing):
- `participations.transport_from_name` — only trimmed in [00235:91-93](../supabase/migrations/00235_logistics_lock_grace_period.sql#L91-L93)
- `seat_requests.pickup_from` — only trimmed in [request_seat](../supabase/migrations/00235_logistics_lock_grace_period.sql#L150-L260) (message field IS stripped, pickup isn't)
- `activity_gear.gear_name` — only trimmed in [set_activity_gear](../supabase/migrations/00235_logistics_lock_grace_period.sql#L99-L160)
- `reports.reason` — only trimmed in `create_report`

**Fix:** Apply `regexp_replace(..., '<[^>]*>', '', 'g')` in each RPC right before the INSERT/UPDATE (same pattern as 00006 wall + 00099 DM).

### H6 — `conversations.request_message` column lacks a CHECK constraint
[00072_connection_request_system.sql:15](../supabase/migrations/00072_connection_request_system.sql#L15) — RPC validates 1–500 chars, column itself has no upper bound. If a future codepath bypasses the RPC, no DB backstop.
**Fix:** `ALTER TABLE conversations ADD CONSTRAINT request_message_len CHECK (request_message IS NULL OR char_length(request_message) BETWEEN 1 AND 500);`.

### H7 — `set_activity_gear` accepts an unbounded JSONB array
[00235:99-160](../supabase/migrations/00235_logistics_lock_grace_period.sql#L99-L160) — no `jsonb_array_length` guard; an attacker passing a million-item array triggers an unbounded loop.
**Fix:** `IF jsonb_array_length(p_items) > 50 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;` at the top of the loop block.

### H8 — `npm audit`: `@xmldom/xmldom` + `fast-uri` high-severity CVEs
Both are *transitive build-time* dependencies (`expo-updates → plist`, `expo-dev-client → ajv`). Not in the app's runtime path on user devices, but they ship in dev builds and could affect local dev environments.
**Fix:** Wait for Expo to bump them in a stable SDK release, or override via `package.json` `"overrides"` if a security review is needed sooner. Low urgency since the app's GPX parser uses regex, not xmldom.

---

## Medium

### M1 — Realtime: `tabs-badges` global subscription for notifications + private_messages
[(tabs)/_layout.tsx:128](../app/(auth)/(tabs)/_layout.tsx#L128) — the agent's read is partly right: subscribing without a `filter` means the server pushes events for ALL rows, and RLS filters at row read time. Event timing therefore leaks (someone is messaging someone, somewhere) even though row content is RLS-gated.
**Fix:** Filter the subscription on `user_id=eq.${currentUserId}` for notifications and `receiver_id=eq.${currentUserId}` for private_messages. Same pattern as `messagerie-incoming`.

### M2 — Realtime: `activities-nearby` global subscription
[use-nearby-activities.ts:24](../src/hooks/use-nearby-activities.ts#L24) — same event-timing leak shape, but lower stakes (an activity's existence is public info anyway).
**Fix:** Acceptable for now; would require a per-bbox filter that doesn't exist in postgres_changes natively.

### M3 — Auth-flow: `checkUserStatus` is fire-and-forget
[use-auth.ts:55-58](../src/hooks/use-auth.ts#L55-L58) — `isAuthenticated` resolves before `needsOnboarding` / `isSuspended`. AuthGate can route into `/(auth)` before knowing the user is suspended or hasn't onboarded; the flash is brief but visible.
**Fix:** Await `checkUserStatus` before setting `isLoading = false`. AuthGate already has guards, this just removes the race.

### M4 — `set_date_of_birth` / `accept_tos` lack advisory locks
[00009_auth_functions.sql:6, :46](../supabase/migrations/00009_auth_functions.sql#L6) — one-time-only checks without a lock; in theory two concurrent calls could both pass the "not yet set" check. Unlikely with normal clients but defence-in-depth.
**Fix:** `PERFORM pg_advisory_xact_lock(hashtext('auth:' || v_user_id::text));` at the top.

### M5 — `send_contact_request` pending-cap is not time-windowed
[00221_send_contact_request_strip_html.sql:73](../supabase/migrations/00221_send_contact_request_strip_html.sql#L73) — 10-pending hard cap, but no per-day rate. An aggressor can keep the cap full by sending fresh ones as old ones expire. Belt-and-suspenders: add 5/day window.

### M6 — Suspended user can briefly view `(auth)` content via back button
[_layout.tsx:79-81](../app/_layout.tsx#L79-L81) — AuthGate redirects on suspension detection but a back-button after the redirect can re-render the previous screen for a frame.
**Fix:** Add a second guard inside `(auth)/_layout.tsx` that returns `<Redirect href="/(visitor)/suspended" />` if `isSuspended`.

### M7 — `npm audit`: `postcss` moderate XSS in stringify
Build-time dep via `@expo/metro-config`. Affects bundler output theoretically; not exploitable at runtime by a user. Will resolve on next Expo SDK upgrade.

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
