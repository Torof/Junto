import { View, StyleSheet } from 'react-native';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { useMemo } from 'react';

// Shared 4-segment vertical level gauge.
// Used in:
//   - SportIconGrid (declared sport breakdown rows)
//   - BadgeDisplay (sport experience chips on the profile body)

const LEVEL_PRIORITY: Record<string, number> = {
  expert: 4,
  avancé: 3,
  intermédiaire: 2,
  débutant: 1,
  // English fallbacks for activities created in EN locale.
  advanced: 3,
  intermediate: 2,
  beginner: 1,
};

const LEVEL_COLORS_BY_DOTS: Record<number, string> = {
  1: '#7EC8A3',
  2: '#F4A373',
  3: '#E5524E',
  4: '#9B6BD6',
};

export function levelStringToDots(level: string | null | undefined): number {
  return LEVEL_PRIORITY[level ?? ''] ?? 0;
}

export function LevelGauge({ dots }: { dots: number }) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const filled = Math.max(0, Math.min(4, dots));
  const color = LEVEL_COLORS_BY_DOTS[filled] ?? '#7EC8A3';
  return (
    <View style={styles.gauge}>
      {[3, 2, 1, 0].map((idx) => {
        const isFilled = idx < filled;
        return (
          <View
            key={idx}
            style={[
              styles.gaugeSeg,
              isFilled ? { backgroundColor: color } : styles.gaugeSegEmpty,
            ]}
          />
        );
      })}
    </View>
  );
}

const createStyles = (colors: AppColors) =>
  StyleSheet.create({
    gauge: {
      width: 5,
      height: 22,
      gap: 2,
      justifyContent: 'flex-end',
      flexShrink: 0,
    },
    gaugeSeg: {
      height: 4,
      borderRadius: 1.5,
    },
    gaugeSegEmpty: {
      backgroundColor: colors.line,
    },
  });
