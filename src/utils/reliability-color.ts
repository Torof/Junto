import type { AppColors } from '@/constants/colors';

// Reliability trust code — 5 distinct, monotonic steps (worst → best) + a
// neutral for "no history yet". Shared by the ReliabilityRing and the
// Discovery card pill so ring and pill can never drift apart.
//   excellent (≥90) → blue (the "verified / elite" top tier, distinct from the
//                     brand green) · good (≥75) → green
//   fair (≥50)      → amber        · poor (<50) → red
//   new (no score)  → neutral grey
export const RELIABILITY_EXCELLENT_COLOR = '#2F6FED'; // blue — top tier, stands apart from the ramp

export function reliabilityColorForScore(score: number | null, colors: AppColors): string {
  if (score === null) return colors.textSecondary;
  if (score >= 90) return RELIABILITY_EXCELLENT_COLOR;
  if (score >= 75) return colors.success;
  if (score >= 50) return colors.warning;
  return colors.error;
}

export function reliabilityColorForTier(tier: string | null | undefined, colors: AppColors): string {
  switch (tier) {
    case 'excellent':
      return RELIABILITY_EXCELLENT_COLOR;
    case 'good':
      return colors.success;
    case 'fair':
      return colors.warning;
    case 'poor':
      return colors.error;
    default:
      return colors.textSecondary; // 'new' / unknown
  }
}
