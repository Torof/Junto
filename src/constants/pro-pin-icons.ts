// Curated environment-icon set for the pro page pushpin (pin system v4).
// A pro picks ONE to identify their univers; it renders on the pushpin head
// and (later) on their page. Keys mirror the DB CHECK constraint + the
// set_pro_pin_icon validation in migration 00280 — keep them in sync.

export interface ProPinIconOption {
  key: string;
  emoji: string;
  label: string;
}

export const PRO_PIN_ICONS: ProPinIconOption[] = [
  { key: 'mountain', emoji: '🏔', label: 'Montagne' },
  { key: 'cliff', emoji: '🪨', label: 'Falaise' },
  { key: 'sea', emoji: '🌊', label: 'Mer' },
  { key: 'river', emoji: '🛶', label: 'Rivière' },
  { key: 'air', emoji: '🪂', label: 'Air' },
  { key: 'snow', emoji: '❄️', label: 'Neige' },
  { key: 'bike', emoji: '🚵', label: 'Vélo' },
  { key: 'forest', emoji: '🌲', label: 'Forêt' },
];

export function getProPinEmoji(key: string | null | undefined): string | null {
  if (!key) return null;
  return PRO_PIN_ICONS.find((i) => i.key === key)?.emoji ?? null;
}
