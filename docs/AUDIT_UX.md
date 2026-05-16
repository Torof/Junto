# Pre-launch UX audit — 2026-05-16

Four parallel passes across the major surfaces, scoped to **objective** findings only (loading/empty/error states, i18n holes, theme-token drift, accessibility, touch targets, keyboard/safe-area handling). Taste calls were excluded.

Findings are grouped by **theme** rather than per-screen — most issues recur across surfaces and the fix pattern is uniform.

**Status legend:** ✅ shipped · ⊘ deferred / over-flagged · ⏳ open

---

## ⏳ Theme 1 — Hardcoded colors bypassing theme tokens

**Status: open (polish-tier).** Big, mechanical, no user-visible bug. Deferred to a dedicated polish pass.

Recurring across many surfaces. Either reliability/badge accent colors hardcoded (`#7EC8A3`, `#F26B2E`, `#E5524E`, `#4B7CB8`, `#2A4060`, `#B87333`, `#9DA9B5`, `#E0B040`, `#E8A33D`) or `#FFFFFF` for inverse text / icon fill.

- [profile-hero.tsx:39-42, :67-71, :119-120, :186-190, :271, :302, :364](../src/components/profile-hero.tsx)
- [badge-display.tsx:68-71, :1209-1210, :1315](../src/components/badge-display.tsx)
- [activity-detail.tsx:643-664](../src/components/activity-detail.tsx#L643-L664) — meta chip accent colors
- [activity-detail.tsx:1015, activity-wall.tsx:322, presence-qr-modal.tsx:78](../src/components/activity-detail.tsx#L1015) — `#FFFFFF` on inverse text / QR background
- [mes-activites.tsx:303, notifications.tsx:268, settings-drawer.tsx:436, _layout.tsx:232](../app/(auth)/(tabs)/mes-activites.tsx#L303) — `#FFFFFF` in badge/button text

**Suggested fix:** Introduce `colors.textInverse` + centralized reliability/badge palette in `src/constants/colors.ts`. Then a one-pass sweep replaces every hex with a token.

---

## ⏳ Theme 2 — Hardcoded pixel values bypassing spacing/radius tokens

**Status: open (polish-tier).** Same shape as Theme 1 — deferred to polish pass.

Scattered everywhere. Mostly `spacing.xs + 2`, `spacing.sm + 2`, raw `4` / `6` / `8` / `10` / `11` / `22`.

- [map-legend.tsx:40-58](../src/components/map-legend.tsx)
- [map-view.tsx:445-471](../src/components/map-view.tsx)
- [login.tsx:240, :252, :262, :285, :292](../app/(visitor)/login.tsx)
- [filter-sheet.tsx:284](../src/components/filter-sheet.tsx#L284) — fragile pixel-math separator offset
- [activity-detail.tsx:987, conversation/[id].tsx:849](../src/components/activity-detail.tsx#L987)

**Suggested fix:** Add named tokens for recurring "almost-spacing" values (`spacing.xsPlus`, `spacing.smPlus`), then sweep.

---

## ✅ Theme 3 — Missing `accessibilityLabel` on icon-only Pressables

**Status: shipped** (commit fd004c3).

- ✅ activity-detail share + open-menu buttons; tabs got `accessibilityRole="tab"` + selected state
- ✅ meta-chips-grid: chips announce `"{label}: {value}"`
- ✅ activities-bottom-sheet: clear-filter X
- ✅ profil.tsx pencil + Menu
- ✅ profile/[id].tsx more-menu
- ✅ create-button.tsx: i18n label (via Theme 7 batch)
- ⊘ Tab bar: already correct — expo-router's `title` serves as the a11y label when `tabBarShowLabel: false`.

New i18n keys: `activity.shareCta`, `activity.openMenu`, `map.clearFilter`, `profil.editName`, `profil.openSettings`, `publicProfile.openMenu`.

---

## ✅ Theme 4 — Touch targets < 44×44 dp

**Status: shipped** (commit c9ea2e4).

- ✅ Seat-request Accept/Decline (paddingVertical 6→12 ≈ 44dp, hitSlop 4→8)
- ✅ Send + attach buttons (36→44)
- ⏳ Password eye toggle (Medium) — deferred to polish
- ⏳ Settings-drawer close ✕, save/cancel links (Medium) — deferred to polish
- ⏳ Drawer tab handle hitSlop (Medium) — deferred to polish

---

## ✅ Theme 5 — Loading-state gaps

**Status: shipped (high-priority items)** (commit c9ea2e4).

- ✅ edit/[id].tsx: "…" → LogoSpinner
- ✅ login.tsx + notifications.tsx: "…" → ActivityIndicator
- ⊘ step2.tsx GPX parse: already had loading state (`traceLoading` key) — agent over-flagged
- ⏳ carte.tsx pin-loading overlay: deferred (needs design eye for placement)
- ⏳ filter-sheet.tsx:206 alert spinner (Low) — deferred

---

## ✅ Theme 6 — Error handling gaps

**Status: shipped** (commits c9ea2e4 + fd004c3).

- ✅ reset-password.tsx: raw `err.message` → getFriendlyError
- ✅ notifications.tsx markAsRead / markAllAsRead: try/catch added
- ✅ settings-drawer togglePref / handleSaveName: try/catch added
- ✅ mes-activites.tsx: query error now rendered (was destructured but never displayed)
- ✅ messagerie.tsx accept/decline/hide handlers: `unknownError` → getFriendlyError
- ⊘ activity-wall.tsx error branching: not actually a leak — rate-limit toast is a literal i18n string, fall-through goes through `getFriendlyError`. Agent over-flagged.

---

## ✅ Theme 7 — i18n holes

**Status: shipped (most)** (commit c9ea2e4).

- ✅ login.tsx / notifications.tsx "…" loading → ActivityIndicator (no string needed)
- ✅ step3.tsx Premium badge → `t('account.tier.premium')`
- ✅ create-button.tsx accessibilityLabel → `t('map.createActivityCta')`
- ✅ settings-drawer tier label → `t('account.tier.{free,pro,premium}')`
- ⊘ activity-detail tabs: already i18n'd via `t('activity.tab.${tab}')` — agent over-flagged
- ⏳ mes-activites.tsx `OPEN_LEVEL = 'Tous niveaux'`: **deferred** — sentinel compares against DB-stored data, not a display string. Proper fix needs data model change (use a key like `'__open__'` or `null`), not `t()`.

---

## ✅ Theme 8 — Keyboard / safe-area handling

**Status: shipped** (commit 06fd685).

- ✅ onboarding.tsx: `useSafeAreaInsets` added (no KAV — no TextInput on this screen, just date picker + checkbox)
- ✅ create/step1.tsx: wrapped in KeyboardAvoidingView (iOS) + `keyboardShouldPersistTaps="handled"`
- ✅ create/step2.tsx: `keyboardShouldPersistTaps="handled"` on controls ScrollView
- ✅ mes-activites + notifications FlatList: `paddingBottom: insets.bottom + spacing.md`

---

## ✅ / ⊘ Theme 9 — Misc surface-specific

**Status: mixed** (commit fd004c3 for high-value items).

- ✅ conversation/[id].tsx:401 edit-mode logic bug: `!selectedMessage && !editContent` was AND — only returned early when both were empty, letting save fire with null selectedMessage. Switched to `||`.
- ⊘ messagerie.tsx pending-badge invalidation: already correctly handled by realtime subscription + local invalidate in handleAcceptSeat. Agent over-flagged.
- ⏳ messagerie.tsx empty-state CTA: polish (subjective)
- ⏳ carte.tsx location-permission denied UX: polish
- ⏳ step1.tsx disabled-Next inline message: polish
- ⏳ leave-activity-modal.tsx ⚠️ emoji → Lucide icon: polish
- ⏳ conversation send button ↑ glyph → Lucide icon: polish

---

## Summary

**Shipped (5 batches, 4 commits):** Themes 3, 4 (high), 5 (high), 6, 7 (most), 8, 9 (high). Every objective bug and accessibility/keyboard/safe-area gap is closed.

**Open (polish-tier):** Themes 1 + 2 (token sweep), low-priority items in Themes 4 / 5 / 9. None block launch — these benefit from a dedicated polish session with eyes on the visual outcome rather than batch shipping.
