// Centralized accent palette per sport_category — the 5 Junto universes
// (pin system v4 / taxonomy v2.1, migrations 00281 + 00282). Used both as the
// activity accent (cards/popups/detail/offerings) and as the pro pushpin disc
// color. Retired-sport categories fall back to the CTA color.
//   mountain green · water blue · air violet · cycling slate · à pied crimson
export const SPORT_CATEGORY_COLORS: Record<string, string> = {
  mountain: '#4A7C59',
  water: '#2563EB',
  air: '#8B5CF6',
  cycling: '#64748B',
  'on-foot': '#E11D48',
};

export function sportCategoryColor(category: string | null | undefined, fallback: string): string {
  if (!category) return fallback;
  return SPORT_CATEGORY_COLORS[category] ?? fallback;
}

function parseHex(hex: string): [number, number, number] {
  const h = hex.replace('#', '');
  const full = h.length === 3 ? h.split('').map((c) => c + c).join('') : h;
  return [parseInt(full.slice(0, 2), 16), parseInt(full.slice(2, 4), 16), parseInt(full.slice(4, 6), 16)];
}

/**
 * Blend two hex colours into an OPAQUE hex (`t` = weight of `a`, 0..1).
 * Used for the channel-card tint: an opaque tint dodges the Android
 * elevation-on-translucent-background artifact (a grey ghost rectangle).
 */
export function mixHex(a: string, b: string, t: number): string {
  const [ar, ag, ab] = parseHex(a);
  const [br, bg, bb] = parseHex(b);
  const w = Math.max(0, Math.min(1, t));
  const ch = (x: number, y: number) => Math.round(x * w + y * (1 - w)).toString(16).padStart(2, '0');
  return `#${ch(ar, br)}${ch(ag, bg)}${ch(ab, bb)}`;
}
