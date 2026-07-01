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
