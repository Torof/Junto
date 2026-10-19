// The 5 pro pushpin universes (pin system v4 / taxonomy v2 + wellness 00461). A pro picks one;
// it sets the pushpin disc color + white glyph (rendered by ProPin). Keys are
// a subset of the 6 activity universes — no "on-foot" (no running guides
// exist). Mirrors the DB pin_icon CHECK + set_pro_pin_icon validation in
// migrations 00281 + 00461 — keep in sync.

export interface ProPinIconOption {
  key: string;
  label: string;
}

export const PRO_PIN_ICONS: ProPinIconOption[] = [
  { key: 'mountain', label: 'Montagne' },
  { key: 'water', label: 'Eau' },
  { key: 'air', label: 'Air' },
  { key: 'cycling', label: 'Vélo' },
  { key: 'wellness', label: 'Bien-être' },
];
