import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

interface Props {
  tier: string | null;
  // Optional override style (e.g. compact text in a popup row).
  size?: 'sm' | 'md';
}

// Same color palette used by ProfileHero's score ring — kept here so the
// chip reads as "this is the same trust signal you'd see on the profile".
const TIER_COLORS: Record<string, string> = {
  excellent: '#7EC8A3',
  good: '#7EC8A3',
  fair: '#F26B2E',
  poor: '#E5524E',
  new: '#9DA9B5',
};

export function ReliabilityTierChip({ tier, size = 'md' }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  if (!tier) return null;
  const color = TIER_COLORS[tier] ?? colors.textMuted;
  const dotSize = size === 'sm' ? 6 : 7;
  return (
    <View style={styles.chip}>
      <View
        style={[
          styles.dot,
          { width: dotSize, height: dotSize, borderRadius: dotSize / 2, backgroundColor: color },
        ]}
      />
      <Text
        style={[styles.label, size === 'sm' && styles.labelSm, { color }]}
        numberOfLines={1}
      >
        {t(`reliability.tier.${tier}`, { defaultValue: tier })}
      </Text>
    </View>
  );
}

const createStyles = (_colors: AppColors) =>
  StyleSheet.create({
    chip: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 5,
    },
    dot: {},
    label: {
      fontSize: 11.5,
      fontWeight: '700',
      letterSpacing: 0.2,
    },
    labelSm: {
      fontSize: 10.5,
    },
  });
