# Presence — v1 Test Plan

Hand-runnable test matrix for the presence subsystem before signing off pre-launch. Tick each box on real devices. Each scenario lists setup, expected user-visible behavior, and where to verify (Sentry breadcrumbs, in-app notif row, DB column).

Last reviewed: 2026-05-03 (post mig 00167 + 00168).

---

## Setup

- Two test accounts (e.g. `scottpanam` and `scottintrip`) — both opted in to background location, push permission granted.
- One real device per account ideally (or one device + account-switch).
- A way to fast-forward time isn't needed — set `starts_at` to a fresh value per test.
- Sentry dashboard open in another tab. Filter to `environment: preview`.

---

## C1. Joiner happy path — geofence (foreground)

**Setup:** Create activity from account A with `starts_at = T+25min`, `requires_presence = TRUE`, location at the meetup point. From account B, request to join → A accepts.

**Steps:**
1. T-25 → T-15: B opens Junto, sees activity in calendar.
2. T-15 → T+15: B walks to meetup point with Junto in foreground.
3. Cross the 300m geofence boundary.

**Expected:**
- Local notif "Présence détectée" fires (sound).
- ~3-5s later, local notif "Présence confirmée" fires (sound, distinct identifier).
- In-app notification list shows `presence_confirmed` row.
- DB: B's `participations.confirmed_present = TRUE`.
- Sentry: `[presence.location] in zone, calling RPC` event with `accuracy_m` ≤ 100, `distance_m` ≤ 300.

---

## C2. Joiner happy path — foreground service (backgrounded mid-window)

**Setup:** Same as C1 but B opens Junto at T-12min (inside the T-15..T+15 window), then minimizes (home button, NOT swipe-kill).

**Expected:**
- Orange persistent notif appears: "Junto valide ta présence — Détection automatique active pendant la fenêtre de présence".
- Walk to meetup point.
- Service detects in-zone → confirmée fires with sound.
- Orange persistent notif disappears (service auto-stopped).
- Sentry: `[presence.fgservice] started` then `[presence.location] all validated, stopping service` (or equivalent).

---

## C3. Joiner happy path — QR scan

**Setup:** Same as C1. B is in geo-zone but for some reason not auto-validated (e.g. B opens app at T+3min after background failed).

**Steps:**
1. A taps "Show QR" in activity-detail (button visible from T-15min).
2. B taps "Scan QR" → camera opens.
3. B scans A's QR.

**Expected:**
- B's `confirm_presence_via_token` succeeds.
- B's `confirmed_present = TRUE`.
- A's `confirmed_present = TRUE` too (creator auto-flip per mig 00163).
- Both get `presence_confirmed` notif (skip_push default true → in-app only, no push).
- Both reliability scores recomputed.

---

## C4. Creator happy path — T-10 reminder + QR availability

**Setup:** Account A creates activity, `starts_at = T+12min`, `requires_presence = TRUE`. Don't open the app between create and T-10.

**Expected:**
- T-10min: push notif arrives — "{activity title}" / "Génère le QR de présence pour tes participants".
- Tap notif → activity-detail opens.
- "Show QR" button is **already visible** (UI gate is T-15min, ≥ 5 min before reminder fired).
- Tap → modal shows QR.
- DB: `notifications` row `type = 'qr_create_reminder'`, `data.activity_id` matches.

---

## C5. Reminder spine — full lifecycle for an unconfirmed participant

**Setup:** Account A creates activity 2h+ in the future, requires_presence. B joins, accepted. **B never validates.**

**Expected pings to B over the lifecycle:**
| Time | Type | Push? | Body |
|---|---|---|---|
| T-2h | `presence_pre_warning` | yes | "Démarre dans 2h — prépare-toi à valider ta présence sur place" |
| T-10min | `presence_pre_warning_10min` | yes | "Démarre dans 10 min — pense à valider ta présence sur place" |
| T+duration/2 | `presence_validate_warning` | yes | "Sinon tu seras enregistré comme absent à {title}" |
| T+duration+1h | `presence_validate_overdue` | yes | "Tu es enregistré comme absent. Demande à tes co-participants de te valider si tu étais bien là." |

**Verify:**
- Push tray shows ONE collapsed entry per activity under `presence-{activity_id}`. Each new push replaces the prior visible one. Title gets `(×2)`, `(×3)`, `(×4)` suffixes as the count grows.
- All four `notifications` rows exist in DB.
- A (the creator) gets `qr_create_reminder` once at T-10min; not the validate-* reminders.

---

## C6. Peer review (3-participant)

**Setup:** A creates activity, B and C join, both accepted. A also accepted (created activity = participant). All three present at meeting point.

**Steps:**
1. A and B auto-validate via geofence/foreground watcher.
2. C doesn't validate (e.g. forgot phone).
3. Activity completes.

**Expected at T+0 after status flip:**
- `rate_participants` notif fires for A, B, C (in-app only).

**Steps continued:**
4. A opens peer review screen, votes "yes, C was there".
5. B opens peer review screen, votes "yes, C was there".

**Expected:**
- C's `confirmed_present` flips TRUE on B's vote (the 2nd) via `peer_validate_presence`.
- C gets `presence_confirmed` notif.
- C's reliability score recomputed.

**At T+22h..T+24h:**
- A's `peer_review_closing` reminder: should NOT fire (A voted on B and C → no unconfirmed peers left).
- B's: should NOT fire (B voted on A and C → none left).
- C's: should NOT fire (C never voted → has unconfirmed peers, but C's own gate — `confirmed_present = TRUE` after the flip — passes; with mig 00166, the OUTER filter on `p.confirmed_present = TRUE` admits C, but the EXISTS clause requires `p2.confirmed_present IS NULL` and excludes the now-flipped peers; so C has nothing to vote on and the reminder doesn't fire). Verify this matches expectation.

---

## C7. Race conditions

**Setup:** Be standing at the meeting point. Cold-start the app at T-10min.

**Expected:**
- Initial-state check fires first → calls validate RPC → server flips `confirmed_present = TRUE`.
- Foreground watcher activates ~1s later → finds B already in zone → calls validate RPC → server idempotent (mig 00163) → returns success no-op.
- Geofence task may also fire if OS detected Enter — same idempotent no-op.
- Foreground service starts → location task fires → same no-op.
- **User hears the confirmée success sound exactly once** (whichever path won the local-notif schedule first; subsequent identical schedules are silent updates on Android).

---

## C8. Edge cases

| Scenario | Expected |
|---|---|
| Activity cancelled at T-5min, B in zone at T+0 | `confirm_presence_via_geo` rejects (mig 00167 status gate). No `confirmed_present` change. |
| Activity soft-deleted (`deleted_at IS NOT NULL`) at T-5min | Same — rejected by mig 00167 deleted_at gate. |
| B withdraws at T-1min (`participations.status = 'withdrawn'`) | Rejected: server requires `status = 'accepted'`. |
| B suspended at T-1min | Rejected: server suspended check. |
| User sends QR scan at T+duration+2h45min (still in via_token window) | Succeeds (window is T+duration+3h). |
| User sends QR scan at T+duration+3h01min | Rejected: outside via_token window. |
| User sends geo at T-15min01s | Rejected: outside via_geo time window. |
| Activity with no participants except creator at T+0 | Cron auto-expires the activity at T+2h with `status = 'expired'`. No reminders fire. |
| User in zone for two back-to-back activities | Geofence task fires once per activity. Each gets its own validation. |

---

## C9. UI surface verification

| Time | Expected on activity-detail UI for creator |
|---|---|
| T-20min | "Show QR" button NOT visible |
| T-15min | "Show QR" button appears |
| T-10min | Push reminder lands; button still visible |
| T+0 | Status flips to "in_progress"; button stays visible |
| T+duration | Status flips to "completed"; button still visible |
| T+duration+1h | Button still visible (UI window is T+duration+1h) |
| T+duration+1h01min | Button hidden |

**Note on UI/server window mismatch:** UI hides the button at T+duration+1h but server `via_token` accepts until T+duration+3h. So a creator who showed the QR earlier and forgot to dismiss the modal could still serve scans for 2h after the button hides. Acceptable.

---

## C10. Closed-app behavior on aggressive Android (Samsung)

**Known OEM ceiling.** Closed-app auto-validation (swipe-killed Junto, OS fires Enter, app wakes, validates) does **not** work on Samsung One UI 10 even with explicit battery-optimization opt-out. This is below our code layer.

**What we ship for users in this scenario:**
- The reminder spine catches them via push (assuming push delivery works — Samsung also kills FCM to apps in stopped state, so this is also OEM-bound).
- QR scan as a manual fallback.
- Peer testimony as a 24h fallback.

**No test required for the closed-app auto-validation case.** Document in onboarding: "Open Junto on the day of the activity for automatic detection. Otherwise, scan the QR or let your peers vote you in."

---

## Sign-off checklist

Before pre-launch sign-off, confirm:

- [ ] C1, C2, C3 pass on a real device for the joiner role.
- [ ] C4 passes on a real device for the creator role.
- [ ] C5 — at least one full lifecycle observed end-to-end (can be compressed by adjusting `starts_at` and waiting through the cron sweep).
- [ ] C6 — 3-account scenario tested at least once.
- [ ] C7 — confirmée sound fires exactly once on cold-start-in-zone.
- [ ] C8 — at least cancelled-at-T-5min and withdrawn-at-T-1min explicitly tested.
- [ ] C9 — QR button visibility transitions verified at T-15min and T+duration+1h.

Anything that fails: open an issue, link the Sentry trace, treat as v1-blocker.
