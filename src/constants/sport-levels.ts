/**
 * Level scales per sport. Granular grade-by-grade for sports that have a real
 * scale (French climbing, Font, alpine, WI, M, canyon v, whitewater class, ski,
 * brevet…). The very low / trivial grades and the +/- sub-grades are dropped on
 * purpose — nobody coordinates an outing around 4c or 6a+. Every sport starts
 * with "Tous niveaux".
 *
 * `description` (when present) is the coarse tier the grade maps to, used both
 * as a chip hint and by the map/list level filter (see levelSpanMatchesTiers).
 */

export interface LevelOption {
  label: string;
  description?: string;
}

const T = { D: 'Débutant', I: 'Intermédiaire', A: 'Avancé', E: 'Expert' } as const;

const GENERIC: LevelOption[] = [
  { label: 'Tous niveaux' },
  { label: 'Débutant' },
  { label: 'Intermédiaire' },
  { label: 'Avancé' },
  { label: 'Expert' },
];

// French sport grades — couenne + grande voie (no +, starts at 5a).
const FRENCH_SPORT: LevelOption[] = [
  { label: 'Tous niveaux' },
  { label: '5a', description: T.D }, { label: '5b', description: T.D }, { label: '5c', description: T.D },
  { label: '6a', description: T.I }, { label: '6b', description: T.I }, { label: '6c', description: T.I },
  { label: '7a', description: T.A }, { label: '7b', description: T.A }, { label: '7c', description: T.A },
  { label: '8a', description: T.E }, { label: '8b', description: T.E }, { label: '8c', description: T.E },
];

// Bouldering — Font scale (no +, starts at 5).
const FONT: LevelOption[] = [
  { label: 'Tous niveaux' },
  { label: '5', description: T.D },
  { label: '6a', description: T.I }, { label: '6b', description: T.I }, { label: '6c', description: T.I },
  { label: '7a', description: T.A }, { label: '7b', description: T.A }, { label: '7c', description: T.A },
  { label: '8a', description: T.E },
];

// Alpine grade — mountaineering.
const ALPINE: LevelOption[] = [
  { label: 'Tous niveaux' },
  { label: 'F', description: T.D },
  { label: 'PD', description: T.I }, { label: 'AD', description: T.I },
  { label: 'D', description: T.A }, { label: 'TD', description: T.A },
  { label: 'ED', description: T.E },
];

// Ice — WI scale.
const ICE: LevelOption[] = [
  { label: 'Tous niveaux' },
  { label: 'WI3', description: T.I },
  { label: 'WI4', description: T.A }, { label: 'WI5', description: T.A },
  { label: 'WI6', description: T.E },
];

// Mixed / dry-tooling — M scale.
const DRYTOOL: LevelOption[] = [
  { label: 'Tous niveaux' },
  { label: 'M5', description: T.I }, { label: 'M6', description: T.I },
  { label: 'M7', description: T.A }, { label: 'M8', description: T.A },
  { label: 'M9', description: T.E },
];

const VIA_FERRATA: LevelOption[] = [
  { label: 'Tous niveaux' },
  { label: 'PD', description: T.D },
  { label: 'AD', description: T.I },
  { label: 'D', description: T.A }, { label: 'TD', description: T.A },
  { label: 'ED', description: T.E },
];

// Canyon — vertical scale (v1 dropped as trivial).
const CANYON: LevelOption[] = [
  { label: 'Tous niveaux' },
  { label: 'v2', description: T.D },
  { label: 'v3', description: T.I }, { label: 'v4', description: T.I },
  { label: 'v5', description: T.A }, { label: 'v6', description: T.A },
  { label: 'v7', description: T.E },
];

// Whitewater class — kayak + rafting.
const WHITEWATER: LevelOption[] = [
  { label: 'Tous niveaux' },
  { label: 'Classe II', description: T.D },
  { label: 'Classe III', description: T.I },
  { label: 'Classe IV', description: T.A },
  { label: 'Classe V', description: T.E },
];

// Ski descent grade — ski touring / freeride / splitboard.
const SKI: LevelOption[] = [
  { label: 'Tous niveaux' },
  { label: 'S1', description: T.D },
  { label: 'S2', description: T.I },
  { label: 'S3', description: T.A }, { label: 'S4', description: T.A },
  { label: 'S5', description: T.E },
];

// Piste colours — ski alpin / snowboard / VTT.
const PISTE: LevelOption[] = [
  { label: 'Tous niveaux' },
  { label: 'Vert', description: T.D },
  { label: 'Bleu', description: T.I },
  { label: 'Rouge', description: T.A },
  { label: 'Noir', description: T.E },
];

// Flying brevets — parapente / speed-riding / deltaplane.
const FLYING: LevelOption[] = [
  { label: 'Tous niveaux' },
  { label: 'Découverte', description: T.D },
  { label: 'Brevet en cours', description: T.D },
  { label: 'Pilote autonome', description: T.I },
  { label: 'Confirmé', description: T.A },
];

const DIVING: LevelOption[] = [
  { label: 'Tous niveaux' },
  { label: 'N1', description: T.D },
  { label: 'N2', description: T.I },
  { label: 'N3', description: T.A },
  { label: 'N4', description: T.E },
];

const APNEA: LevelOption[] = [
  { label: 'Tous niveaux' },
  { label: 'Découverte', description: T.D },
  { label: '10-20 m', description: T.I },
  { label: '20-30 m', description: T.A },
  { label: '30 m+', description: T.E },
];

export const SPORT_LEVEL_SCALES: Record<string, LevelOption[]> = {
  'climbing-sport': FRENCH_SPORT,
  'climbing-multipitch': FRENCH_SPORT,
  bouldering: FONT,
  mountaineering: ALPINE,
  'ice-climbing': ICE,
  'dry-tooling': DRYTOOL,
  'via-ferrata': VIA_FERRATA,
  canyoning: CANYON,
  kayaking: WHITEWATER,
  canoe: WHITEWATER,
  rafting: WHITEWATER,
  'ski-touring': SKI,
  'ski-freeride': SKI,
  splitboard: SKI,
  skiing: PISTE,
  snowboarding: PISTE,
  'mtb-xc': PISTE,
  'mtb-enduro': PISTE,
  'mtb-downhill': PISTE,
  paragliding: FLYING,
  'speed-riding': FLYING,
  'hang-gliding': FLYING,
  diving: DIVING,
  freediving: APNEA,
};

/** The explicit "open to everyone" option — index 0 of every scale. */
export const OPEN_LEVEL = 'Tous niveaux';

/** Coarse difficulty tiers used by the map/list level filter. */
export const LEVEL_TIERS = ['Débutant', 'Intermédiaire', 'Avancé', 'Expert'] as const;

function levelTierIndex(sportKey: string, label: string | null | undefined): number | null {
  if (!label || label === OPEN_LEVEL) return null;
  const option = getLevelScale(sportKey).find((o) => o.label === label);
  const tierName = option?.description ?? option?.label;
  const idx = tierName ? (LEVEL_TIERS as readonly string[]).indexOf(tierName) : -1;
  return idx === -1 ? null : idx;
}

/**
 * Does an activity's level span [level, levelMax] overlap any of the selected
 * tiers? Empty selection matches everything; open / unmappable levels soft-fail.
 */
export function levelSpanMatchesTiers(
  sportKey: string,
  level: string | null | undefined,
  levelMax: string | null | undefined,
  selectedTiers: readonly string[],
): boolean {
  if (selectedTiers.length === 0) return true;
  const lo = levelTierIndex(sportKey, level);
  if (lo === null) return true;
  const hiRaw = levelTierIndex(sportKey, levelMax);
  const hi = hiRaw ?? lo;
  const low = Math.min(lo, hi);
  const high = Math.max(lo, hi);
  return selectedTiers.some((tier) => {
    const i = (LEVEL_TIERS as readonly string[]).indexOf(tier);
    return i >= low && i <= high;
  });
}

/** Get the appropriate level scale for a given sport. Falls back to generic. */
export function getLevelScale(sportKey: string): LevelOption[] {
  return SPORT_LEVEL_SCALES[sportKey] ?? GENERIC;
}

/**
 * Format a level span for display.
 *   - open / empty     → "Tous niveaux" (or '')
 *   - single level     → "6a"
 *   - contiguous range → "5c → 7a"
 */
export function formatLevelRange(
  level: string | null | undefined,
  levelMax: string | null | undefined,
): string {
  if (!level) return '';
  if (level === OPEN_LEVEL) return OPEN_LEVEL;
  if (!levelMax || levelMax === level) return level;
  return `${level} → ${levelMax}`;
}

/**
 * Which sports use distance + D+ as their primary difficulty metrics.
 */
export const SPORTS_WITH_DISTANCE = new Set<string>([
  'hiking', 'trekking', 'trail-running', 'running', 'cycling', 'gravel',
  'mtb-xc', 'mtb-enduro', 'mtb-downhill',
  'cross-country-ski', 'snowshoeing',
]);

export const SPORTS_WITH_ELEVATION = new Set<string>([
  'hiking', 'trekking', 'trail-running', 'running', 'cycling', 'gravel',
  'mtb-xc', 'mtb-enduro', 'mtb-downhill',
  'ski-touring', 'ski-freeride', 'splitboard',
  'cross-country-ski', 'snowshoeing', 'mountaineering',
]);

export function sportHasDistance(sportKey: string): boolean {
  return SPORTS_WITH_DISTANCE.has(sportKey);
}

export function sportHasElevation(sportKey: string): boolean {
  return SPORTS_WITH_ELEVATION.has(sportKey);
}

/**
 * Format the primary difficulty signal for a card.
 *   1. distance + D+ (if sport uses them AND at least one is set)
 *   2. level range (fallback)
 */
export function formatDifficultySignal(
  sportKey: string,
  level: string | null | undefined,
  distanceKm: number | null | undefined,
  elevationGainM: number | null | undefined,
  levelMax?: string | null,
): string {
  const parts: string[] = [];
  if (sportHasDistance(sportKey) && distanceKm != null && distanceKm > 0) {
    parts.push(`${Number(distanceKm).toLocaleString('fr-FR')} km`);
  }
  if (sportHasElevation(sportKey) && elevationGainM != null && elevationGainM > 0) {
    parts.push(`D+ ${elevationGainM.toLocaleString('fr-FR')} m`);
  }
  if (parts.length > 0) return parts.join(' · ');
  return formatLevelRange(level, levelMax);
}
