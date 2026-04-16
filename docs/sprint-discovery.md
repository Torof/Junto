# Sprint — Discovery (Partenaires + Demandes)

**Status:** planned, not yet implemented.
**Scope decision:** 2026-04-16.

---

## 1. Goal

Ship a Discovery feature that lets opted-in users find activity partners via mutual geographic consent and a gated request-to-chat flow. Solves Junto's cold-start problem at launch, especially given the flyer/QR distribution strategy.

**Non-goal:** anything that reads as a dating app. See §3.

---

## 2. Why now

- Launch is on-demand (flyer/QR in gyms, bakeries, clubs). By design, early users land in low-density regions with no activities visible — they need *something* to do on first open.
- Feature reuses existing infrastructure (profiles, private messaging, reliability score, PostGIS, notifications). Additive, not disruptive.
- No testers yet, no revenue, no analytics blocker. The only opportunity cost is ~2-3 days of other planned work (analytics), which is itself premature without users.

---

## 3. Anti-dating scope lock

These constraints are non-negotiable. Any proposed sub-feature that violates them is rejected.

- **No dating-app mechanics:** no swipe deck, no match entity, no "it's a match!", no hearts, no sparkles, no mutual-reveal, no "someone viewed your profile", no likes, no superlikes, no boosts, no premium visibility.
- **No bio.** Junto profiles already have no bio by design. Discovery inherits that.
- **No gender field.** Not collected, not displayed.
- **Reliability + badges + activity count** are the dominant trust signals, not appearance.
- **Random-generated pseudonyms at signup** encourage functional identity over personal branding.
- **Pre-seeded request flow** is required — no cold DMs from discovery.
- **Mutual geographic consent** — bidirectional radius intersection. No unilateral exposure.
- **No "recently viewed", no "interested in you"** — passive exposure only.
- **No monetization gates** on discovery — no revenue incentive to distort product.
- **Decline is silent** — sender never knows they were declined.
- **Language watch-list:** never use "match", "connect", "find people", "meet someone". Use "partenaires", "demande de contact", "accepter / décliner".

---

## 4. User stories

1. *As a new Junto user in a low-density region, I want to see other active users in my area so I have someone to coordinate with even when no activities are posted.*
2. *As an existing user, I want to opt into being discovered so people with matching interests can reach me without me exposing myself globally.*
3. *As a user receiving a contact request, I want to review it (with context: sport + period) and accept or silently decline.*
4. *As a user who has sent a request, I want to see it's still pending and optionally cancel it.*
5. *As a user whose request is declined, I do not want to know. I do not want to be able to re-send to the same person.*

---

## 5. Data model

### 5.1 Columns added to `users`

| Column | Type | Constraints | Notes |
|---|---|---|---|
| `discovery_enabled` | BOOLEAN | NOT NULL DEFAULT FALSE | Opt-in toggle. |
| `discovery_center` | GEOGRAPHY(POINT, 4326) | NULL allowed | User-picked center, not GPS. |
| `discovery_radius_km` | INTEGER | NULL allowed, CHECK 10–200 | 10km steps enforced in UI. |
| `discovery_sport_keys` | TEXT[] | NULL allowed, each key must exist in `sports.key` | Multi-select. |
| `discovery_transport` | TEXT[] | NULL allowed, values ∈ (`car`, `carpool`, `public_transport`, `bike`, `other`) | Multi-select, optional. |

All five columns added to the `handle_user_update` whitelist trigger as client-modifiable. If `discovery_enabled=TRUE`, then `discovery_center`, `discovery_radius_km`, `discovery_sport_keys` must all be non-null (enforced in function, not constraint).

### 5.2 Columns added to `conversations`

| Column | Type | Constraints | Notes |
|---|---|---|---|
| `status` | TEXT | NOT NULL DEFAULT 'active', CHECK IN ('pending_request', 'active', 'declined') | Existing rows backfill to 'active'. |
| `initiated_from` | TEXT | NULL allowed, CHECK IN ('discovery', 'direct') | For future extensibility. |
| `request_expires_at` | TIMESTAMPTZ | NULL allowed | Set when status = 'pending_request'; NOW() + 30 days. |

### 5.3 New RPC functions (all SECURITY DEFINER)

See §6 for authorization chains.

- `get_discovery_partners() RETURNS SETOF discovery_partner_row`
- `update_discovery_settings(p_enabled, p_center_lng, p_center_lat, p_radius_km, p_sport_keys, p_transport)`
- `send_contact_request(p_target_user_id UUID, p_message TEXT, p_sport_key TEXT, p_period TEXT)`
- `accept_contact_request(p_conversation_id UUID)`
- `decline_contact_request(p_conversation_id UUID)`
- `cancel_contact_request(p_conversation_id UUID)`

### 5.4 Views / queries

- Existing `messagerie` query splits by `status`:
  - Active conversations → primary list.
  - Pending (as recipient) → Reçues section of Demandes.
  - Pending (as sender) → Envoyées section of Demandes.
  - Declined → invisible to sender, invisible to recipient (hard delete or soft hide — decide in §7 open questions).

---

## 6. Authorization chains (per CLAUDE.md rule — these need Scott's sign-off before any function is written)

### 6.1 `get_discovery_partners()`

1. Auth check (`auth.uid() IS NULL` → reject).
2. Caller's suspension check (`suspended_at IS NOT NULL` → reject).
3. Caller's `discovery_enabled` check — must be TRUE (can't see partners without opting in yourself).
4. Caller has non-null `discovery_center`, `discovery_radius_km`, `discovery_sport_keys`.
5. Return: users WHERE
   - `discovery_enabled = TRUE`
   - `suspended_at IS NULL`
   - `id != auth.uid()`
   - At least one shared sport key with caller (`discovery_sport_keys && caller.discovery_sport_keys`)
   - Bidirectional radius intersection: `ST_DWithin(caller.center, their.center, caller.radius + their.radius)` — if their zones overlap at all, they're visible to each other
   - Not blocked by caller and not blocking caller (join against `blocked_users`)
6. Return only public-profile columns + reliability_score + activity_count + sport overlap + distance from caller's center.
7. Sort by reliability_score DESC, activity_count DESC.
8. REVOKE EXECUTE from `anon`.

### 6.2 `update_discovery_settings(...)`

1. Auth check.
2. Suspension check.
3. Validate inputs:
   - If `p_enabled=TRUE`, all required fields non-null.
   - Radius in [10, 200].
   - Sport keys exist in `sports` table.
   - Transport values in enum set.
4. Use `set_config('junto.bypass_lock', 'true', true)` to allow UPDATE on the whitelisted columns.
5. UPDATE own user row.
6. REVOKE EXECUTE from `anon`.

### 6.3 `send_contact_request(p_target_user_id, p_message, p_sport_key, p_period)`

1. Auth check.
2. Suspension check (caller).
3. Target existence + not suspended.
4. Target ≠ caller.
5. Not blocked (either direction).
6. Target has `discovery_enabled = TRUE`.
7. Sport key is shared between the two discovery profiles.
8. Period in ('weekend', 'month', 'ongoing').
9. Rate limit — advisory lock on caller UUID:
   - Count pending requests from caller → reject if ≥ 10.
   - Check for existing pending or active conversation with target → reject.
10. Message content length in [1, 2000], strip HTML.
11. Create `conversations` row (caller + target ordered pair, `status='pending_request'`, `initiated_from='discovery'`, `request_expires_at=NOW()+30 days`).
12. Create `private_messages` row with the message content.
13. Create notification for target (type `contact_request`, no content in body — privacy).
14. REVOKE EXECUTE from `anon`.

### 6.4 `accept_contact_request(p_conversation_id)`

1. Auth check.
2. Suspension check (caller).
3. Conversation exists + status = 'pending_request'.
4. Caller is the recipient (not the sender) of this conversation.
5. Flip status to 'active'.
6. Clear `request_expires_at`.
7. Notification to sender (type `contact_request_accepted`, generic text, no content reveal).
8. REVOKE EXECUTE from `anon`.

### 6.5 `decline_contact_request(p_conversation_id)`

1. Auth check.
2. Suspension check.
3. Conversation exists + status = 'pending_request'.
4. Caller is the recipient.
5. Flip status to 'declined'.
6. No notification to sender (silent).
7. REVOKE EXECUTE from `anon`.

### 6.6 `cancel_contact_request(p_conversation_id)`

1. Auth check.
2. Conversation exists + status = 'pending_request'.
3. Caller is the sender.
4. Hard delete or soft status (TBD — see open questions).
5. REVOKE EXECUTE from `anon`.

### 6.7 Auto-expiration

- Edge function (or pg_cron equivalent) runs daily: for all `conversations` with `status='pending_request'` AND `request_expires_at < NOW()`, transition to `declined` (no notifications).

### 6.8 Cascade handling

- If A blocks B: any `pending_request` between A and B is marked declined (no notifications).
- If user is suspended: their `discovery_enabled` is forced to FALSE; all their pending requests (sent or received) are marked declined.

---

## 7. UI flows

### 7.1 Discovery opt-in

Screen: `app/(auth)/discovery/settings.tsx` (or modal).

- Toggle: "Activer la découverte".
- When ON:
  - Map pin picker: select center point (reuse activity creation flow).
  - Radius slider: 10–200 km, 10km steps, default 50km.
  - Sport multi-select: uses existing SportDropdown component.
  - Transport multi-select (optional): Car, Covoiturage, TC, Vélo, Autre.
- Save button hits `update_discovery_settings` RPC.

### 7.2 Discovery tab — Partenaires

Screen: `app/(auth)/(tabs)/discovery.tsx`.

Segmented control at top: **Partenaires** | **Demandes**.

Partenaires list:
- Each row: avatar (40px) + pseudo + sport icons with level + reliability emoji + activity count + distance ("à 12 km").
- Sorted by reliability_score DESC, activity_count DESC.
- Tap → full public profile screen (existing).
- From public profile, new button: "Envoyer une demande de contact".
- Empty state: "Active la découverte pour voir des partenaires". If no matches despite opt-in: "Aucun partenaire pour l'instant — essaye d'élargir ton rayon ou d'ajouter des sports."

### 7.3 Contact request modal

Modal triggered from the profile screen.

- Header: "Envoyer une demande à [Pseudo]".
- Row 1 — Sport picker: chips of sports shared between the two (tap to select one).
- Row 2 — Period picker: chips "ce weekend" / "ce mois-ci" / "à voir ensemble".
- Below: auto-generated message (editable):
  `"Salut ! Je t'ai vu sur la découverte. Tu serais partant·e pour faire [ski de rando] [ce weekend] ?"`
- Send button hits `send_contact_request` RPC.
- On success → toast "Demande envoyée", close modal.
- Error states: rate limit, already sent, target blocked.

### 7.4 Discovery tab — Demandes

- Top section: **Reçues** — list of pending requests with: sender avatar + pseudo + reliability + sport + period + message text + Accepter / Décliner buttons.
- Collapsible: **Envoyées** — list of pending requests you sent + Annuler button. Shows recipient pseudo, sport, period, sent-ago.
- Empty state: "Aucune demande en attente".

### 7.5 Message board swap

- On `carte.tsx`, the floating AlertButton icon changes from `BellPlus` to `Radar` (Lucide).

### 7.6 Accepted flow

- Sender gets push notification "Ta demande a été acceptée" (no content reveal).
- Conversation appears in both users' Messagerie with regular message threading.
- Pre-seeded message is the first message in the thread.

### 7.7 Declined flow

- Recipient: conversation disappears from Demandes list. No trace.
- Sender: nothing happens, ever. No notification, no status update. Rate limit (1-per-pair) prevents re-sending.

---

## 8. i18n keys to add

FR + EN:
- `discovery.tab` (tab label)
- `discovery.enable` / `discovery.disable`
- `discovery.settingsTitle`
- `discovery.centerPicker`
- `discovery.radius`, `discovery.radiusKm`
- `discovery.sports`, `discovery.transport`
- `discovery.transport.car`, `.carpool`, `.public_transport`, `.bike`, `.other`
- `discovery.partners`, `discovery.requests`
- `discovery.sendRequest`, `discovery.cancelRequest`
- `discovery.acceptRequest`, `discovery.declineRequest`
- `discovery.emptyPartners`, `discovery.emptyRequests`
- `discovery.messageTemplate` (with `{sport}` and `{period}` placeholders)
- `discovery.period.weekend`, `.month`, `.ongoing`
- `discovery.requestSent`, `.requestAccepted`
- `discovery.distance` (e.g. "à {{km}} km")
- Notification titles: `notif.contactRequest.title`, `notif.contactRequestAccepted.title`

---

## 9. Scope staging

- **Ship 1** (this sprint): Partenaires + Demandes flow.
- **Ship 2** (future, only if Ship 1 proves itself): Annonces wall (§10 below).

Do not build Annonces now. Ship, watch, decide.

---

## 10. Deferred — Annonces (wall of open calls)

Out of scope for this sprint. Idea preserved for future:
- One active "call" per user per sport at a time.
- Sport + level + period + region + optional 200-char note.
- Appears in a third tab of Discovery.
- Reply button → pre-seeded conversation (reuse `send_contact_request` with `initiated_from='annonce'`).

Risks to re-evaluate before building: potential to cannibalize activity creation (users post calls instead of activities because friction is lower). If Ship 1 usage shows users creating activities from matches, build Annonces. If Ship 1 usage is low, Annonces won't help.

---

## 11. Open questions (resolve before Phase B migrations)

1. **Declined conversations**: hard delete or soft hide via status? Soft hide preserves audit history but clutters the table; hard delete is cleaner but loses moderation signal. Lean: soft hide (status='declined') + periodic cleanup after 90 days.
2. **Cancellation of sent requests**: hard delete, status='cancelled' new state, or revert to 'declined'? Lean: new 'cancelled' status for clarity, treat same as declined for visibility.
3. **Minimum activity count floor**: any anti-spam gating? Decision: no, per Scott. Add later if spam.
4. **Request message content size**: max 500 chars? 2000? Lean: 500 — this is a greeting, not an essay.
5. **Notification for declined requests**: silent as specified, but does Sentry track the decline event for funnel analytics? Out of scope for this sprint.

---

## 12. Checklist before writing code

- [ ] Scott validates the §6 authorization chains.
- [ ] Open questions §11 resolved.
- [ ] Sprint doc merged to main.
- [ ] `docs/DECISIONS.md` entry added.
- [ ] `docs/BACKLOG.md` updated (Ship 1 items added, Annonces parked).
- [ ] Memory file updated with final scope.

Once these are green, Phase B (migrations) starts.
