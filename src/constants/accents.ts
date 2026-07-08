// Curated accent palette. The app's accent lives in a single theme token
// (`cta`); Settings lets a user override it live and the whole app recolors
// (333+ token usages). Extend by appending — array order is display order.
//
// Each `hex` applies to BOTH light and dark themes and is vetted to hold white
// button text at least as well as the original orange (the app's baseline).
// Decorative multi-hue sets (profile stat trio, activity meta rainbow) and
// semantic scales (reliability, page-type badge) deliberately do NOT follow
// this token — see the accent-feature notes.
export interface Accent {
  key: string;
  hex: string;
}

export const ACCENTS: Accent[] = [
  { key: 'orange', hex: '#F26B2E' }, // current base identity
  { key: 'mountain', hex: '#3F7A56' },
  { key: 'meadow', hex: '#2E8B57' },
  { key: 'vif', hex: '#2FA46A' },
  { key: 'pine', hex: '#216B5E' },
  { key: 'sage', hex: '#6E8A5E' },
  { key: 'glacier', hex: '#4A86B8' },
  { key: 'slate', hex: '#41648C' },
  { key: 'terracotta', hex: '#B15A38' },
];

// The light-theme default `cta` — used to highlight the active swatch when no
// explicit override is set (accent === null).
export const DEFAULT_ACCENT_HEX = '#F26B2E';
