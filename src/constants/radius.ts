export const radius = {
  xs: 2,
  sm: 4,
  md: 6,
  lg: 8,
  // Soft card corner — the Gen-D surface language (canon 2026-09-19):
  // borderless cards on the page canvas round at `card`, not `md`.
  card: 16,
  // Large soft corner for bottom sheets / drawers (Google place-sheet feel).
  xl: 24,
  full: 999,
} as const;
