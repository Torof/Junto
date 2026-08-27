import type { AppColors } from '@/constants/colors';

// Reliability trust code — 5 distinct, monotonic steps (worst → best) + a
// neutral for "no history yet". Shared by the ReliabilityRing and the
// Discovery card pill so ring and pill can never drift apart.
//   excellent (≥90) → green   · good (≥75) → lime
//   fair (≥50)      → amber   · poor (<50) → red
//   new (no score)  → neutral grey
export const RELIABILITY_GOOD_COLOR = '#8BC34A'; // lime — distinct from the excellent green

export function reliabilityColorForScore(score: number | null, colors: AppColors): string {
  if (score === null) return colors.textSecondary;
  if (score >= 90) return colors.success;
  if (score >= 75) return RELIABILITY_GOOD_COLOR;
  if (score >= 50) return colors.warning;
  return colors.error;
}

export function reliabilityColorForTier(tier: string | null | undefined, colors: AppColors): string {
  switch (tier) {
    case 'excellent':
      return colors.success;
    case 'good':
      return RELIABILITY_GOOD_COLOR;
    case 'fair':
      return colors.warning;
    case 'poor':
      return colors.error;
    default:
      return colors.textSecondary; // 'new' / unknown
  }
}
