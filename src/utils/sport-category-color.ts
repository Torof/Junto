// Centralized accent palette per sport_category. Used by chips/pills that
// display the sport label so users can read the activity "type" at a glance.
// Falls back to the CTA orange for unknown / outdoor / generic categories.

export const SPORT_CATEGORY_COLORS: Record<string, string> = {
  mountain: '#4A7C59',
  road: '#3B82F6',
  water: '#06B6D4',
  air: '#0EA5E9',
  urban: '#A78BFA',
  ball: '#F97316',
  endurance: '#E11D48',
};

export function sportCategoryColor(category: string | null | undefined, fallback: string): string {
  if (!category) return fallback;
  return SPORT_CATEGORY_COLORS[category] ?? fallback;
}
