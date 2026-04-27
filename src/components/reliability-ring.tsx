import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import Svg, { Circle } from 'react-native-svg';
import { useTranslation } from 'react-i18next';
import { fontSizes } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

type Tier = 'excellent' | 'good' | 'fair' | 'poor' | 'new';

interface Props {
  // Pass `score` only on own-profile (raw value is private). For other users,
  // pass `tier` — the ring fills to the band midpoint and the label shows the
  // tier name instead of a percentage.
  score?: number | null;
  tier?: Tier | string | null;
  size: number;
  strokeWidth?: number;
  showLabel?: boolean;
  children: React.ReactNode;
}

function colorFor(score: number, colors: AppColors): string {
  if (score >= 75) return colors.success;
  if (score >= 50) return colors.warning;
  if (score >= 25) return colors.warning;
  return colors.error;
}

function tierToScore(tier: string): number | null {
  switch (tier) {
    case 'excellent': return 95;
    case 'good': return 82;
    case 'fair': return 62;
    case 'poor': return 30;
    default: return null;
  }
}

// Leave a visible gap at the top so the ring reads as a meter, not a border.
const GAP_DEGREES = 10;
const ARC_FRACTION = (360 - GAP_DEGREES) / 360;

export function ReliabilityRing({ score, tier, size, strokeWidth = 10, showLabel = true, children }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const outerSize = size + strokeWidth * 2 + 6;
  const center = outerSize / 2;
  const svgRadius = (size + strokeWidth) / 2;
  const fullCircumference = 2 * Math.PI * svgRadius;
  const arcLength = fullCircumference * ARC_FRACTION;

  const effectiveScore = score ?? (tier ? tierToScore(tier) : null);
  const clamped = effectiveScore !== null ? Math.max(0, Math.min(100, effectiveScore)) : 0;
  const progress = clamped / 100;
  const filledLength = arcLength * progress;
  const ringColor = effectiveScore !== null ? colorFor(clamped, colors) : colors.surface;

  // Gap is on the right side (3-o'clock position). Arc starts just after
  // the gap and goes clockwise around to just before the gap.
  const startRotation = GAP_DEGREES / 2;

  const styles = useMemo(() => createStyles(colors), [colors]);

  return (
    <View style={[styles.container, { width: outerSize, height: outerSize }]}>
      <Svg width={outerSize} height={outerSize} style={StyleSheet.absoluteFill}>
        {/* Track (grey arc with gap) */}
        <Circle
          cx={center}
          cy={center}
          r={svgRadius}
          stroke={colors.surface}
          strokeWidth={strokeWidth}
          fill="none"
          strokeDasharray={`${arcLength} ${fullCircumference - arcLength}`}
          strokeLinecap="round"
          rotation={startRotation}
          origin={`${center}, ${center}`}
        />
        {/* Filled arc */}
        {score !== null && filledLength > 0 && (
          <Circle
            cx={center}
            cy={center}
            r={svgRadius}
            stroke={ringColor}
            strokeWidth={strokeWidth}
            fill="none"
            strokeDasharray={`${filledLength} ${fullCircumference - filledLength}`}
            strokeLinecap="round"
            rotation={startRotation}
            origin={`${center}, ${center}`}
          />
        )}
      </Svg>
      <View style={styles.content}>
        {children}
      </View>
      {/* Score label at the gap */}
      {showLabel && (
        <View style={styles.scoreBadge}>
          {score != null ? (
            <Text style={[styles.scoreText, { color: ringColor }]}>{clamped}%</Text>
          ) : tier ? (
            <Text style={[styles.scoreText, { color: ringColor }]}>{t(`reliability.tier.${tier}`)}</Text>
          ) : null}
          <Text style={styles.scoreLabel}>{t('reliability.label')}</Text>
        </View>
      )}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: {
    alignItems: 'center',
    justifyContent: 'center',
  },
  content: {
    position: 'absolute',
  },
  scoreBadge: {
    position: 'absolute',
    right: -4,
    alignSelf: 'center',
    backgroundColor: colors.background,
    paddingHorizontal: 4,
    borderRadius: 4,
  },
  scoreText: {
    fontSize: fontSizes.xs - 1,
    fontWeight: 'bold',
  },
  scoreLabel: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs - 2,
    opacity: 0.7,
  },
});
