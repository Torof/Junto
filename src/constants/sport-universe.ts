import { sportCategoryColor } from '@/utils/sport-category-color';

// Static sport_key → universe (category) map, mirroring the sports table
// (taxonomy v2.1, migs 00281 + 00282 — locked). Lets <SportIcon> self-tint
// without a DB lookup at every call site; surfaces that already carry
// sport_category keep using it directly.
export const SPORT_UNIVERSE: Record<string, string> = {
  // air
  paragliding: 'air', skydiving: 'air', 'speed-riding': 'air', 'hang-gliding': 'air',
  // cycling
  cycling: 'cycling', 'mtb-xc': 'cycling', 'mtb-enduro': 'cycling', 'mtb-downhill': 'cycling', gravel: 'cycling',
  // mountain
  'cross-country-ski': 'mountain', 'ice-climbing': 'mountain', mountaineering: 'mountain',
  'climbing-sport': 'mountain', 'climbing-multipitch': 'mountain', 'ski-touring': 'mountain',
  bouldering: 'mountain', skiing: 'mountain', 'dry-tooling': 'mountain', caving: 'mountain',
  snowboarding: 'mountain', snowshoeing: 'mountain', 'ski-freeride': 'mountain',
  splitboard: 'mountain', 'via-ferrata': 'mountain',
  // on-foot
  hiking: 'on-foot', running: 'on-foot', 'trail-running': 'on-foot', trekking: 'on-foot', football: 'on-foot',
  // water
  canyoning: 'water', diving: 'water', kayaking: 'water', rafting: 'water', sailing: 'water',
  'stand-up-paddle': 'water', surfing: 'water', swimming: 'water', freediving: 'water', canoe: 'water',
  windsurfing: 'water', wakeboard: 'water',
};

/** Universe colour for a sport key (T1 tint). Falls back to the given colour. */
export function sportIconColor(sportKey: string, fallback: string): string {
  return sportCategoryColor(SPORT_UNIVERSE[sportKey], fallback);
}
