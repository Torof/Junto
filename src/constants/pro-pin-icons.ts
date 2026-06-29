// The 4 pro pushpin universes (pin system v4 / taxonomy v2). A pro picks one;
// it sets the pushpin disc color + white glyph (rendered by ProPin). Keys are
// a subset of the 5 activity universes — no "running" (no running guides
// exist). Mirrors the DB pin_icon CHECK + set_pro_pin_icon validation in
// migration 00281 — keep in sync.

export interface ProPinIconOption {
  key: string;
  label: string;
}

export const PRO_PIN_ICONS: ProPinIconOption[] = [
  { key: 'mountain', label: 'Montagne' },
  { key: 'water', label: 'Eau' },
  { key: 'air', label: 'Air' },
  { key: 'cycling', label: 'Vélo' },
];
