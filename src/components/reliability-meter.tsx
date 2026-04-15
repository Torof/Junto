import { View, Text, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';

interface Props {
  score: number | null;
  compact?: boolean;
}

function colorFor(score: number): string {
  if (score >= 90) return colors.success;
  if (score >= 70) return colors.warning;
  return colors.error;
}

export function ReliabilityMeter({ score, compact = false }: Props) {
  const { t } = useTranslation();

  if (score === null) {
    return (
      <View style={[styles.container, compact && styles.containerCompact]}>
        <Text style={styles.emptyText}>{t('reliability.notEnoughData')}</Text>
      </View>
    );
  }

  const clamped = Math.max(0, Math.min(100, score));
  const barColor = colorFor(clamped);

  return (
    <View style={[styles.container, compact && styles.containerCompact]}>
      <View style={styles.row}>
        <Text style={styles.label}>{t('reliability.label')}</Text>
        <Text style={[styles.value, { color: barColor }]}>{clamped}%</Text>
      </View>
      <View style={styles.track}>
        <View style={[styles.fill, { width: `${clamped}%`, backgroundColor: barColor }]} />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    width: '100%',
    gap: spacing.xs,
  },
  containerCompact: {
    gap: 4,
  },
  row: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'baseline',
  },
  label: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
    fontWeight: 'bold',
  },
  value: {
    fontSize: fontSizes.md,
    fontWeight: 'bold',
  },
  track: {
    height: 6,
    borderRadius: radius.full,
    backgroundColor: colors.surface,
    overflow: 'hidden',
  },
  fill: {
    height: '100%',
    borderRadius: radius.full,
  },
  emptyText: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontStyle: 'italic',
  },
});
