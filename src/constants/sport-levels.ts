/**
 * Level scales per sport.
 * For sports with a dedicated technical scale (climbing grades, alpine grades,
 * ski pistes...), use that. For sports without one, use the generic débutant/
 * intermédiaire/avancé/expert scale.
 * Every sport includes 'Tous niveaux' as an explicit open option.
 */

export interface LevelOption {
  /** Short label shown on cards/popups/details */
  label: string;
  /** Optional longer description shown in the selector / tooltip */
  description?: string;
}

const GENERIC: LevelOption[] = [
  { label: 'Tous niveaux' },
  { label: 'Débutant' },
  { label: 'Intermédiaire' },
  { label: 'Avancé' },
  { label: 'Expert' },
];

// Sport-specific scales
const CLIMBING: LevelOption[] = [
  { label: 'Tous niveaux' },
  { label: '5a - 5c', description: 'Débutant' },
  { label: '6a - 6b', description: 'Intermédiaire' },
  { label: '6c - 7a', description: 'Avancé' },
  { label: '7b+', description: 'Expert' },
];

const MOUNTAINEERING: LevelOption[] = [
  { label: 'Tous niveaux' },
  { label: 'F', description: 'Facile' },
  { label: 'PD', description: 'Peu difficile' },
  { label: 'AD', description: 'Assez difficile' },
  { label: 'D', description: 'Difficile' },
  { label: 'TD+', description: 'Très difficile et plus' },
];

const PARAGLIDING: LevelOption[] = [
  { label: 'Tous niveaux' },
  { label: 'Découverte', description: 'Baptême, première sortie' },
  { label: 'Brevet en cours', description: 'Élève pilote' },
  { label: 'Pilote autonome', description: 'Brevet pilote' },
  { label: 'Confirmé', description: 'Brevet + 50h+' },
];

const SKI_TOURING: LevelOption[] = [
  { label: 'Tous niveaux' },
  { label: 'Débutant', description: 'Pentes < 30°' },
  { label: 'Intermédiaire', description: '30-35°' },
  { label: 'Avancé', description: '35°+, glacier' },
  { label: 'Engagé', description: 'Hors-piste technique' },
];

const MTB: LevelOption[] = [
  { label: 'Tous niveaux' },
  { label: 'Vert', description: 'Facile' },
  { label: 'Bleu', description: 'Intermédiaire' },
  { label: 'Rouge', description: 'Difficile' },
  { label: 'Noir', description: 'Expert' },
];

const VIA_FERRATA: LevelOption[] = [
  { label: 'Tous niveaux' },
  { label: 'F', description: 'Facile' },
  { label: 'PD', description: 'Peu difficile' },
  { label: 'AD', description: 'Assez difficile' },
  { label: 'D', description: 'Difficile' },
  { label: 'ED', description: 'Extrêmement difficile' },
];

const CANYONING: LevelOption[] = [
  { label: 'Tous niveaux' },
  { label: 'v1', description: 'Débutant, peu technique' },
  { label: 'v2-v3', description: 'Intermédiaire' },
  { label: 'v4-v5', description: 'Avancé, rappels + sauts' },
  { label: 'v6-v7', description: 'Expert, engagement fort' },
];

const ICE_CLIMBING: LevelOption[] = [
  { label: 'Tous niveaux' },
  { label: 'WI2-WI3', description: 'Débutant' },
  { label: 'WI4', description: 'Intermédiaire' },
  { label: 'WI5', description: 'Avancé' },
  { label: 'WI6+', description: 'Expert' },
];

export const SPORT_LEVEL_SCALES: Record<string, LevelOption[]> = {
  climbing: CLIMBING,
  mountaineering: MOUNTAINEERING,
  paragliding: PARAGLIDING,
  'ski-touring': SKI_TOURING,
  'mountain-biking': MTB,
  'via-ferrata': VIA_FERRATA,
  canyoning: CANYONING,
  'ice-climbing': ICE_CLIMBING,
};

/** Get the appropriate level scale for a given sport. Falls back to generic. */
export function getLevelScale(sportKey: string): LevelOption[] {
  return SPORT_LEVEL_SCALES[sportKey] ?? GENERIC;
}

/** Backwards-compat: the old flat generic list (used by existing code) */
export const LEVELS = ['débutant', 'intermédiaire', 'avancé', 'expert'] as const;

/** Lookup a level's description (for ⓘ tooltip) from its label */
export function getLevelDescription(sportKey: string, label: string): string | undefined {
  const scale = getLevelScale(sportKey);
  return scale.find((l) => l.label === label)?.description;
}

/**
 * Which sports use distance + D+ as their primary difficulty metrics.
 * For these sports, cards show "25 km · D+ 1400m" instead of the generic level.
 */
export const SPORTS_WITH_DISTANCE = new Set<string>([
  'hiking',
  'trail-running',
  'running',
  'cycling',
  'mountain-biking',
  'cross-country-ski',
]);

export const SPORTS_WITH_ELEVATION = new Set<string>([
  'hiking',
  'trail-running',
  'running',
  'cycling',
  'mountain-biking',
  'ski-touring',
  'cross-country-ski',
  'mountaineering',
]);

export function sportHasDistance(sportKey: string): boolean {
  return SPORTS_WITH_DISTANCE.has(sportKey);
}

export function sportHasElevation(sportKey: string): boolean {
  return SPORTS_WITH_ELEVATION.has(sportKey);
}

/**
 * Format the primary difficulty signal for a card.
 * Priority:
 *   1. distance + D+ (if sport uses them AND at least one is set)
 *   2. level (fallback)
 */
export function formatDifficultySignal(
  sportKey: string,
  level: string | null | undefined,
  distanceKm: number | null | undefined,
  elevationGainM: number | null | undefined,
): string {
  const parts: string[] = [];
  if (sportHasDistance(sportKey) && distanceKm != null && distanceKm > 0) {
    parts.push(`${Number(distanceKm).toLocaleString('fr-FR')} km`);
  }
  if (sportHasElevation(sportKey) && elevationGainM != null && elevationGainM > 0) {
    parts.push(`D+ ${elevationGainM.toLocaleString('fr-FR')} m`);
  }
  if (parts.length > 0) return parts.join(' · ');
  return level || '';
}
