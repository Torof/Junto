export const sportIcons: Record<string, string> = {
  hiking: '🥾',
  climbing: '🧗',
  'ski-touring': '⛷',
  'trail-running': '🏃',
  mountaineering: '🏔',
  cycling: '🚴',
  'mountain-biking': '🚵',
  kayaking: '🛶',
  surfing: '🏄',
  sailing: '⛵',
  paragliding: '🪂',
  skiing: '⛷',
  snowboarding: '🏂',
  running: '🏃',
  swimming: '🏊',
};

export function getSportIcon(sportKey: string): string {
  return sportIcons[sportKey] ?? '🏅';
}
