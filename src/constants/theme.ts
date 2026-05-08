// Junto visual conventions (May 2026 reset, brutalist direction):
//
//   - Borders: 1px solid `borderStrong` (not StyleSheet.hairlineWidth —
//     hairline renders as 0.5–0.66 on most devices and reads as vague).
//     Soft dividers inside cards keep using `line` / `lineStrong`.
//   - Radius: cards & surfaces top out at `md` (6). `lg` (8) is the
//     ceiling, not the default. Chips/inputs reach for `xs`/`sm`.
//   - Buttons: content-width by default. Full-width is opt-in via an
//     explicit prop or style override — never the implicit default.
//   - Density: information rows target ≤56pt tall. Reach for `xs`/`sm`
//     spacing aggressively; treat `lg`/`xl` as exceptional.

export { colors } from './colors';
export { spacing } from './spacing';
export { radius } from './radius';
export { fonts, fontSizes } from './typography';
