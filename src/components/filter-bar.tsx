import { useEffect, useMemo, useRef } from 'react';
import { Animated, View, Text, Pressable, StyleSheet } from 'react-native';
import { SlidersHorizontal } from 'lucide-react-native';
import { useTranslation } from 'react-i18next';
import { spacing, radius, fontSizes } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import { useMapStore } from '@/store/map-store';
import type { AppColors } from '@/constants/colors';

interface Props {
  onPress: () => void;
  blink?: boolean;
}

// Top-center "Filtres" pill (Scott 2026-06-10). Replaces the bottom-
// right icon-only button so the discovery action sits near the eye
// line rather than buried in the bottom stack. Active count rides as
// a numeric badge on the leading icon.
export function FilterButton({ onPress, blink = false }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const { filters } = useMapStore();
  const activeCount =
    filters.sportKeys.length
    + (filters.dateMode !== 'all' ? 1 : 0)
    + filters.levelTiers.length
    + filters.visibilities.length
    + (filters.radiusKm !== null ? 1 : 0);
  const hasActive = activeCount > 0;
  const styles = useMemo(() => createStyles(colors), [colors]);
  const scale = useRef(new Animated.Value(1)).current;
  const opacity = useRef(new Animated.Value(1)).current;

  useEffect(() => {
    if (!blink) {
      scale.setValue(1);
      opacity.setValue(1);
      return;
    }
    const loop = Animated.loop(
      Animated.sequence([
        Animated.parallel([
          Animated.timing(scale, { toValue: 1.15, duration: 450, useNativeDriver: true }),
          Animated.timing(opacity, { toValue: 0.6, duration: 450, useNativeDriver: true }),
        ]),
        Animated.parallel([
          Animated.timing(scale, { toValue: 1, duration: 450, useNativeDriver: true }),
          Animated.timing(opacity, { toValue: 1, duration: 450, useNativeDriver: true }),
        ]),
      ]),
    );
    loop.start();
    return () => loop.stop();
  }, [blink, scale, opacity]);

  return (
    <Animated.View style={[styles.wrapper, { transform: [{ scale }], opacity }]}>
      <Pressable
        style={[styles.button, hasActive && styles.buttonActive]}
        onPress={onPress}
        hitSlop={8}
        accessibilityLabel={t('map.openFilters')}
      >
        <View>
          <SlidersHorizontal size={16} color={hasActive ? colors.cta : colors.textPrimary} strokeWidth={2.4} />
          {hasActive && (
            <View style={styles.badge}>
              <Text style={styles.badgeText}>{activeCount}</Text>
            </View>
          )}
        </View>
        <Text style={[styles.label, hasActive && styles.labelActive]}>
          {t('map.filters', { defaultValue: 'Filtres' })}
        </Text>
      </Pressable>
    </Animated.View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  // Full-width wrapper so the chip itself can self-center horizontally.
  wrapper: {
    position: 'absolute',
    top: spacing.md,
    left: 0,
    right: 0,
    alignItems: 'center',
    zIndex: 10,
  },
  button: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: spacing.md,
    paddingVertical: 8,
    backgroundColor: colors.surface,
    borderRadius: radius.full,
    borderWidth: 1,
    borderColor: colors.border,
    elevation: 4,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.15,
    shadowRadius: 4,
  },
  buttonActive: {
    borderColor: colors.cta,
  },
  label: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '700',
    letterSpacing: 0.3,
  },
  labelActive: {
    color: colors.cta,
  },
  badge: {
    position: 'absolute',
    top: -6,
    right: -8,
    minWidth: 14,
    height: 14,
    paddingHorizontal: 3,
    borderRadius: 7,
    backgroundColor: colors.cta,
    alignItems: 'center',
    justifyContent: 'center',
  },
  badgeText: {
    color: colors.background,
    fontSize: 9,
    fontWeight: '800',
  },
});
