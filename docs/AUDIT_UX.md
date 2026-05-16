# Pre-launch UX audit — 2026-05-16

Four parallel passes across the major surfaces, scoped to **objective** findings only (loading/empty/error states, i18n holes, theme-token drift, accessibility, touch targets, keyboard/safe-area handling). Taste calls were excluded.

Findings are grouped by **theme** rather than per-screen — most issues recur across surfaces and the fix pattern is uniform. Each theme has a representative file:line list, not exhaustive.

---

## Theme 1 — Hardcoded colors bypassing theme tokens

Recurring across many surfaces. Either reliability/badge accent colors hardcoded (`#7EC8A3`, `#F26B2E`, `#E5524E`, `#4B7CB8`, `#2A4060`, `#B87333`, `#9DA9B5`, `#E0B040`, `#E8A33D`) or `#FFFFFF` for inverse text / icon fill.

- [profile-hero.tsx:39-42, :67-71, :119-120, :186-190, :271, :302, :364](../src/components/profile-hero.tsx)
- [badge-display.tsx:68-71, :1209-1210, :1315](../src/components/badge-display.tsx)
- [activity-detail.tsx:643-664](../src/components/activity-detail.tsx#L643-L664) — meta chip accent colors
- [activity-detail.tsx:1015, activity-wall.tsx:322, presence-qr-modal.tsx:78](../src/components/activity-detail.tsx#L1015) — `#FFFFFF` on inverse text / QR background
- [mes-activites.tsx:303, notifications.tsx:268, settings-drawer.tsx:436, app/(auth)/(tabs)/_layout.tsx:232](../app/(auth)/(tabs)/mes-activites.tsx#L303) — `#FFFFFF` in badge/button text

**Suggested fix:** Introduce a `colors.textInverse` token + a centralized reliability/badge palette in `src/constants/colors.ts`. Then a one-pass sweep replaces every hex with a token. Enables future dark/light symmetry without re-touching screens.

---

## Theme 2 — Hardcoded pixel values bypassing spacing/radius tokens

Scattered everywhere. Mostly `spacing.xs + 2`, `spacing.sm + 2`, raw `4` / `6` / `8` / `10` / `11` / `22` etc. Examples:

- [map-legend.tsx:40-58](../src/components/map-legend.tsx)
- [map-view.tsx:445-471](../src/components/map-view.tsx)
- [login.tsx:240, :252, :262, :285, :292](../app/(visitor)/login.tsx)
- [filter-sheet.tsx:284](../src/components/filter-sheet.tsx#L284) — fragile pixel-math separator offset
- [activity-detail.tsx:987, conversation/[id].tsx:849](../src/components/activity-detail.tsx#L987)

**Suggested fix:** Add named tokens for the recurring "almost-spacing" values (`spacing.xsPlus = 10`, `spacing.smPlus = 18`) and the radius siblings; then the same one-pass sweep.

---

## Theme 3 — Missing `accessibilityLabel` on icon-only Pressables

Icon buttons across the app announce nothing to screen readers.

- [activity-detail.tsx:229-232](../src/components/activity-detail.tsx#L229) — share / more-menu
- [activity-detail.tsx:579-587](../src/components/activity-detail.tsx#L579) — tab indicators (also missing `accessibilityRole="tab"`)
- [meta-chips-grid.tsx:39-42](../src/components/meta-chips-grid.tsx#L39)
- [profil.tsx:69, :75-76 + profile/[id].tsx:118-120](../app/(auth)/(tabs)/profil.tsx#L69) — pencil / menu / more
- [activities-bottom-sheet.tsx:42](../src/components/activities-bottom-sheet.tsx#L42) — drawer tab handle
- [_layout.tsx:161](../app/(auth)/(tabs)/_layout.tsx#L161) — tab bar (`tabBarShowLabel: false` without alt)
- [create-button.tsx:22](../src/components/create-button.tsx#L22) — hardcoded English label

**Suggested fix:** Add `accessibilityLabel={t('...')}` to every icon-only Pressable. Tab bar needs `accessibilityLabel` per tab.

---

## Theme 4 — Touch targets < 44×44 dp

Apple HIG / Material both recommend 44. Several actionable buttons are below.

- **High**: [conversation/[id].tsx:787-807](../app/(auth)/conversation/[id].tsx#L787) — seat-request Accept/Decline (36×36, safety-critical)
- **High**: [conversation/[id].tsx:1069](../app/(auth)/conversation/[id].tsx#L1069) — send button (36×36)
- **Medium**: [reset-password.tsx:119-121](../app/(visitor)/reset-password.tsx#L119) — password eye toggle
- **Medium**: [settings-drawer.tsx:157, :180-186](../src/components/settings-drawer.tsx#L157) — close ✕, save/cancel links
- **Medium**: [activities-bottom-sheet.tsx:42](../src/components/activities-bottom-sheet.tsx#L42) — tab handle hitSlop only 6

**Suggested fix:** Bump width/height to 44 (or add `hitSlop={8}` so effective target is ≥ 48).

---

## Theme 5 — Loading-state gaps

- **High**: [carte.tsx:91](../app/(auth)/(tabs)/carte.tsx#L91) — `useNearbyActivities` data fetched but `isPending` not surfaced; pins-loading is invisible.
- **High**: [edit/[id].tsx:104-109](../app/(auth)/edit/[id].tsx#L104) — "…" text only, no spinner/skeleton.
- **High**: [step2.tsx:42-68](../app/(auth)/create/step2.tsx#L42) — GPX parsing has `isLoadingTrace` flag but no visible spinner.
- **Low**: [filter-sheet.tsx:206](../src/components/filter-sheet.tsx#L206) — alert query has no spinner.

**Suggested fix:** Surface `isPending` in each, render a `LogoSpinner` or skeleton.

---

## Theme 6 — Error handling gaps

- **High**: [reset-password.tsx:76](../app/(visitor)/reset-password.tsx#L76) — raw `err.message` leak (missed by H3 sweep).
- **High**: [activity-wall.tsx:136-140](../src/components/activity-wall.tsx#L136) — error branches on `err.message.includes('Operation not permitted')` before falling through; raw message can still leak in the fall-through.
- **High**: [notifications.tsx:113-139](../app/(auth)/(tabs)/notifications.tsx#L113) and [settings-drawer.tsx:114-146](../src/components/settings-drawer.tsx#L114) — `markAsRead`, `markAllAsRead`, `togglePref`, `handleSaveName` have no try/catch.
- **High**: [mes-activites.tsx:55](../app/(auth)/(tabs)/mes-activites.tsx#L55) — query `error` destructured but never displayed.

**Suggested fix:** Apply `getFriendlyError` consistently + wrap silent mutations in try/catch with a `Burnt.toast` on failure.

---

## Theme 7 — i18n holes

Hardcoded strings that should be translated:

- [mes-activites.tsx:23](../app/(auth)/(tabs)/mes-activites.tsx#L23) — `'Tous niveaux'`
- [login.tsx:214](../app/(visitor)/login.tsx#L214) — `'...'` loading
- [notifications.tsx:183](../app/(auth)/(tabs)/notifications.tsx#L183) — `'…'` loading
- [step3.tsx:63, :66](../app/(auth)/create/step3.tsx#L63) — `Premium`, `✓` badges
- [create-button.tsx:22](../src/components/create-button.tsx#L22) — `'Create activity'` accessibilityLabel
- [settings-drawer.tsx:148](../src/components/settings-drawer.tsx#L148) — `Pro` / `Premium` / `Free` tier labels
- [activity-detail.tsx:579-587](../src/components/activity-detail.tsx#L579) — tab indicators if any string is raw

---

## Theme 8 — Keyboard / safe-area handling

- **High**: [onboarding.tsx:62-104](../app/(visitor)/onboarding.tsx#L62) — no `KeyboardAvoidingView`, no safe-area insets. Bottom inputs hide under keyboard, top content sits under notch.
- **Medium**: [step2.tsx:104-139](../app/(auth)/create/step2.tsx#L104) — ScrollView missing `keyboardShouldPersistTaps="handled"`.
- **Medium**: [step1.tsx:55-73](../app/(auth)/create/step1.tsx#L55) — TextInput inside ScrollView without KAV; description textarea may be obscured by keyboard.
- **Medium**: [mes-activites.tsx:242, notifications.tsx:226](../app/(auth)/(tabs)/mes-activites.tsx#L242) — FlatList `contentContainerStyle` doesn't pad for `insets.bottom`; rows hide under tab bar on devices with home indicator.

---

## Theme 9 — Misc surface-specific

- **Medium**: [messagerie.tsx:262-266](../app/(auth)/(tabs)/messagerie.tsx#L262) — pending-request badge doesn't invalidate when a seat is accepted from the home tab; manual refresh needed.
- **Medium**: [messagerie.tsx:328-330](../app/(auth)/(tabs)/messagerie.tsx#L328) — empty state doesn't distinguish "you haven't started a conversation" vs "nobody messaged you". Could add a CTA.
- **Low**: [conversation/[id].tsx:401](../app/(auth)/conversation/[id].tsx#L401) — edit-mode validation uses `!selectedMessage && !editDraft.trim()`; should be `||` (logic bug — save fires when selectedMessage is null).
- **Low**: [carte.tsx](../app/(auth)/(tabs)/carte.tsx) — no UX when location permission denied; map loads but nothing tells the user why pins aren't centered.
- **Low**: [step1.tsx Next button](../app/(auth)/create/step1.tsx) — disabled state has no inline message explaining why.
- **Low**: [leave-activity-modal.tsx:28](../src/components/leave-activity-modal.tsx#L28) — `⚠️` emoji instead of a Lucide icon (platform-rendering variance).
- **Low**: [conversation/[id].tsx:1111](../app/(auth)/conversation/[id].tsx#L1111) — send button uses literal `↑` glyph instead of a Lucide icon.

---

## Suggested fix order (my recommendation)

1. **Themes 5 + 6 + 7** — actual UX bugs (silent failures, raw errors, untranslated strings). Ship soon. ~1 batch.
2. **Theme 4** — touch targets, two high-priority spots (seat actions, send button). Quick.
3. **Theme 8** — onboarding KAV + safe-area + tab-bar FlatList padding. Mostly mechanical.
4. **Theme 3** — accessibility labels. One-shot sweep file by file.
5. **Themes 1 + 2** — token sweep. Big, mechanical, low urgency for launch (no user-visible bug); do as a polish pass.
6. **Theme 9** — case-by-case. Some are real (conversation edit logic bug), some are nice-to-haves.
