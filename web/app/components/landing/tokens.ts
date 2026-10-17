// Landing v4 — "la carte vivante" (maquette validée 2026-10-17,
// canvas 2PqvqtoLhTxdU9mVVk784Z). Same tokens as the app's white theme.

export const INK = '#1F1A15';
export const MUTED = '#6B6259';
export const SURFACE_ALT = '#F1EFEA';
export const FOREST = '#0F1A14';
export const MINT = '#7BD8A5';
export const CTA = '#2FA46A';
export const LOGO_GREEN = '#3F7A56';
export const PRO_BLUE = '#2563EB';
export const PRO_TINT = '#E6EEFB';
export const RELIABILITY_BLUE = '#2F6FED';
export const HAIRLINE = 'rgba(31,26,21,0.32)';
export const HAIRLINE_SOFT = 'rgba(31,26,21,0.16)';

// Universe colours — identical to src/utils/sport-category-color.ts in the app.
export type Universe = 'mountain' | 'water' | 'air' | 'cycling' | 'on-foot';
export const UNIVERSE_COLOR: Record<Universe, string> = {
  mountain: '#4A7C59',
  water: '#2563EB',
  air: '#8B5CF6',
  cycling: '#64748B',
  'on-foot': '#E11D48',
};
export const UNIVERSE_LABEL: Record<Universe, string> = {
  mountain: 'Montagne',
  water: 'Eau',
  air: 'Air',
  cycling: 'Vélo',
  'on-foot': 'À pied',
};

export function universeColor(category: string | null | undefined): string {
  return UNIVERSE_COLOR[(category ?? '') as Universe] ?? CTA;
}

// FR labels for the app's sport keys (public.sports.key).
export const SPORT_LABEL: Record<string, string> = {
  bouldering: 'Bloc', canoe: 'Canoë', canyoning: 'Canyoning', caving: 'Spéléo',
  'climbing-multipitch': 'Grande voie', 'climbing-sport': 'Escalade', 'cross-country-ski': 'Ski de fond',
  cycling: 'Vélo de route', diving: 'Plongée', 'dry-tooling': 'Dry-tooling', football: 'Football',
  freediving: 'Apnée', gravel: 'Gravel', 'hang-gliding': 'Deltaplane', hiking: 'Randonnée',
  'ice-climbing': 'Cascade de glace', kayaking: 'Kayak', mountaineering: 'Alpinisme',
  'mtb-downhill': 'VTT descente', 'mtb-enduro': 'VTT enduro', 'mtb-xc': 'VTT', paragliding: 'Parapente',
  rafting: 'Rafting', running: 'Course à pied', sailing: 'Voile', 'ski-freeride': 'Freeride',
  'ski-touring': 'Ski de rando', skiing: 'Ski', skydiving: 'Parachutisme', snowboarding: 'Snowboard',
  snowshoeing: 'Raquettes', 'speed-riding': 'Speed-riding', splitboard: 'Splitboard',
  'stand-up-paddle': 'Paddle', surfing: 'Surf', swimming: 'Natation', 'trail-running': 'Trail',
  trekking: 'Trek', 'via-ferrata': 'Via ferrata', wakeboard: 'Wakeboard', windsurfing: 'Planche à voile',
};

export function sportLabel(key: string | null | undefined): string {
  if (!key) return 'Sport';
  return SPORT_LABEL[key] ?? key.replace(/-/g, ' ');
}

// Normalise for accent-insensitive search.
export function norm(x: string | null | undefined): string {
  return (x ?? '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
}
