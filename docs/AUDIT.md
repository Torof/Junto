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

### C1 — `delete_own_account` leaves `auth.users` orphaned
Account deletion calls a SECURITY DEFINER RPC ([00042_delete_account.sql:55](../supabase/migrations/00042_delete_account.sql#L55)) that purges `public.users` and dependent tables, but **no edge function** calls `supabase.auth.admin.deleteUser()` (only `supabase/functions/send-push` exists). The auth row persists with a working JWT, dangling references to a public profile that no longer exists.
**Fix:** Add a `delete-account` edge function that verifies the caller's JWT, calls the RPC, then `supabase.auth.admin.deleteUser(user_id)` with `service_role`. Wire `settings-drawer.tsx:321` to invoke it instead of the RPC directly.

### C2 — `wall_messages` SELECT policy doesn't filter suspended authors
[00006_messages.sql:20-34](../supabase/migrations/00006_messages.sql#L20-L34) — wall threads remain visible to participants even after the author is suspended. Per SECURITY.md, suspended users' content should drop out of feeds.
**Fix:** Add `AND wall_messages.user_id NOT IN (SELECT id FROM users WHERE suspended_at IS NOT NULL)` to the policy.

### C3 — `private_messages` SELECT policy doesn't filter suspended senders
[00031_conversations_and_messaging.sql:53-68](../supabase/migrations/00031_conversations_and_messaging.sql#L53-L68) — same gap as C2 for DMs. Threads from suspended users stay visible.
**Fix:** Add `AND private_messages.sender_id NOT IN (SELECT id FROM users WHERE suspended_at IS NOT NULL)`.

### C4 — `conversations` SELECT policy exposes suspended counterparties
[00031_conversations_and_messaging.sql:25-35](../supabase/migrations/00031_conversations_and_messaging.sql#L25-L35) — even with C3 fixed, the conversation row leaks `last_message_at` and the other user's ID when the counterparty is suspended.
**Fix:** Require both `user_1` and `user_2` to be non-suspended in the SELECT policy.

---

## High

### H1 — Logistics RPCs reject submissions at the activity-start boundary
Migration 00233 added `AND starts_at > NOW()` to six logistics RPCs without a grace period. A client save at `T-0.5s` that lands at `T+0.5s` is silently rejected. Across six functions ([00233:56](../supabase/migrations/00233_lock_logistics_after_start.sql#L56), `:135`, `:229`, `:372`, `:491`, `:552`).
**Fix:** Switch to `starts_at > NOW() - INTERVAL '5 seconds'` (or `15s`) to absorb clock skew + in-flight latency.

### H2 — `seat_requests.status` CHECK missing `'expired'`
[00076_seat_requests.sql:11](../supabase/migrations/00076_seat_requests.sql#L11) accepts only `pending/accepted/declined`. Later migrations (00142+) write `'expired'`, which the CHECK should refuse. Either no `'expired'` value is actually being written, or the constraint was dropped silently — verify and reconcile.
**Fix:** Migration to either add `'expired'` to the CHECK or document why writes are happening through a SECURITY DEFINER path that bypasses it.

### H3 — Raw error messages leak to user alerts
`err.message` shown directly to users in:
- [activity-detail.tsx:470, :472](../src/components/activity-detail.tsx#L470)
- [conversation/[id].tsx:311, :353](../app/(auth)/conversation/[id].tsx#L311)
- [create/step2.tsx:60, :62](../app/(auth)/create/step2.tsx#L60)
- [peer-review/[id].tsx:96, :114](../app/(auth)/peer-review/[id].tsx#L96) — only catches `'Operation not permitted'`, falls through for everything else.

**Fix:** Wrap every catch in `getFriendlyError(err, '<key>')`. Per CLAUDE.md "Generic error messages only".

### H4 — Type-cast bypass in `conversation-service.ts`
[conversation-service.ts:36, :38, :100, :176](../src/services/conversation-service.ts#L36) uses `.from('conversations' as 'users')` and `as unknown as { ... }` to silence Supabase's generated types. Hides schema drift — a column rename or table change wouldn't trigger a compile error.
**Fix:** Use proper generated types; only cast `as unknown` for RPC return shapes that genuinely lack codegen.

---

## Medium

### M1 — `give_reputation_badge` missing bidirectional block guard
Latest version [00159_dead_artifact_sweep.sql:212-291](../supabase/migrations/00159_dead_artifact_sweep.sql#L212-L291). Blocked users can still vote on each other for completed activities. The pattern from `request_seat` ([00215](../supabase/migrations/00215_request_seat_block_guard.sql)) should apply.
**Fix:** Add `IF EXISTS (SELECT 1 FROM blocked_users WHERE (blocker_id, blocked_id) IN ((v_user_id, p_voted_id), (p_voted_id, v_user_id))) THEN RAISE EXCEPTION ...` before the participation check.

### M2 — `get_user_reputation` + `get_user_trophies` skip auth/suspension checks
[00154:127-174](../supabase/migrations/00154_level_vote_per_sport.sql#L127) and [00134:14-62](../supabase/migrations/00134_badge_system_overhaul.sql#L14-L62). Read-only, but a suspended user can still query reputation data — inconsistent with the documented baseline.
**Fix:** Add the standard `IF auth.uid() IS NULL THEN RETURN; END IF;` + suspension check at the top of each, matching 00226's pattern.

### M3 — Sentry scrubber misses `display_name`
[src/lib/sentry.ts:5-27](../src/lib/sentry.ts#L5-L27) — `SENSITIVE_KEYS` redacts `email`, `phone`, lat/lng, but not `display_name`. Display names are PII (real names common in MVP user set).
**Fix:** Add `'display_name'` (and `'name'`, `'full_name'`) to `SENSITIVE_KEYS`.

### M4 — `trace()` helper doesn't scrub `data` before adding breadcrumb
[src/lib/sentry.ts:129](../src/lib/sentry.ts#L129) — relies on `beforeSend` to clean payloads. If a breadcrumb drops before send (buffer flush, network), raw `data` may exit the device.
**Fix:** Call `scrub(data)` inline before `Sentry.addBreadcrumb`.

### M5 — Push notification payload forwards raw `NEW.data` jsonb
[00162:116](../supabase/migrations/00162_notif_flow_fixes_round2.sql#L116) — `push_notification_to_device()` posts `COALESCE(NEW.data, '{}'::jsonb)` straight to the edge function. Current notifications carry only `activity_id`, but a future migration could add lat/lng or message snippets, which then land on the lock screen.
**Fix:** Add an allow-list of keys forwarded to the device; everything else stays in `notifications` for in-app rendering.

### M6 — Avatar upload trusts client-reported MIME
[src/utils/avatar-upload.ts:25](../src/utils/avatar-upload.ts#L25) — `asset.mimeType` is spoofable. `ImageManipulator.manipulateAsync()` re-encodes, which mitigates exec risk, but the validation itself is paper-thin.
**Fix:** After `manipulateAsync`, verify the first 4 bytes of the buffer match a known image magic number (JPEG / PNG / WEBP). Reject otherwise.

### M7 — Reads referencing logistics state aren't time-gated
Migration 00233 locked WRITES once `starts_at > NOW()`. Functions that read or notify on transport/seat/gear state (audit cross-cut from agent 6) may surface stale state during the in_progress window if any in-flight write was rejected.
**Fix:** Audit functions that emit notifications referencing `seat_requests.status`, `participations.transport_*`, `activity_gear`. Either also gate them, or document why post-start reads are acceptable.

### M8 — Documentation drift in 00232 comment on directional block filter
[00232_get_activity_participants_public.sql:25](../supabase/migrations/00232_get_activity_participants_public.sql#L25) — comment says "anyone the caller has blocked is hidden" but doesn't note that the reverse direction (B blocks A → B still sees A in A's activity participants) is intentional, matching SECURITY.md "Liste participants (Unidirectionnel)".
**Fix:** One-line clarification in the comment.

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
