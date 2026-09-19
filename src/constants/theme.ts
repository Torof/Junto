// Junto visual canon (Sept 2026 unification — supersedes the May 2026
// brutalist charter; validated by Scott, see docs/sprint-unification-ui.md):
//
//   - Surfaces: borderless cards on the page canvas, `radius.card` (16),
//     separated by soft warm shadow (`shadows.card`) OR whitespace — never
//     border + shadow together. 1px borders survive ONLY on inputs and as
//     bottom separators in dense lists. Sheets round at `radius.xl` (24).
//   - Typography: ONE strong voice per surface. 800 is reserved for the
//     title and true accents (badge counts, pill text on solid fills);
//     section labels 700; body 500–600; meta `textSecondary` 400–500.
//     Never the strings 'bold'/'900' — numeric weights only.
//   - Pills/chips: ONE grammar — soft tint (`color + '1A'` bg, no border,
//     `radius.full`, weight 600). Active/selected = solid fill + `onCta`.
//     Use the shared <Chip>.
//   - Buttons: three shapes only, via the shared <AppButton> —
//     `primary` (solid cta pill, `onCta` 700 text, optional glow()),
//     `link` (icon + 600 `textSecondary` text, no box),
//     `icon` (round 40, surface bg). No bordered ghosts with shadows.
//   - Feedback: every tappable responds — wrap in <PressableScale>
//     (default pressed opacity+scale) instead of bare Pressable.
//   - Shadows: warm tokens (`shadows.*`) or `glow(color)` — no inline
//     recipes, no cold '#000' shadows.
//   - Color: tokens only; text on solid accent fills = `colors.onCta`.
//     No emoji in UI labels (lucide + SportIcon).

export { colors } from './colors';
export { spacing } from './spacing';
export { radius } from './radius';
export { fonts, fontSizes } from './typography';
export { shadows, glow } from './shadows';
