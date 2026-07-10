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

// Filter button — icon-only round control (label dropped, Scott
// 2026-07-10). Positioned by the parent (carte.tsx) inside the
// top-left controls row next to the map-style icon (Scott 2026-06-10).
export function FilterButton({ onPress, blink = false }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const { filters } = useMapStore();
  const activeCount =
    filters.sportKeys.length
    + (filters.dateMode !== 'all' ? 1 : 0)
    + filters.levelTiers.length
    + filters.visibilities.length
    + (filters.radiusKm !== null ? 1 : 0)
    // A hidden entity-type category is an active filter too — otherwise a
    // user who unchecks Utilisateurs/Pros sees no badge and doesn't realise
    // a whole category is hidden.
    + (!filters.showActivities ? 1 : 0)
    + (!filters.showProOfferings ? 1 : 0);
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
    <Animated.View style={{ transform: [{ scale }], opacity }}>
      <Pressable
        style={[styles.button, hasActive && styles.buttonActive]}
        onPress={onPress}
        hitSlop={8}
        accessibilityLabel={t('map.openFilters')}
      >
        <View>
          <SlidersHorizontal size={18} color={hasActive ? colors.cta : colors.textPrimary} strokeWidth={2.4} />
          {hasActive && (
            <View style={styles.badge}>
              <Text style={styles.badgeText}>{activeCount}</Text>
            </View>
          )}
        </View>
      </Pressable>
    </Animated.View>
  );
}

// Entity-type toggles — Utilisateurs / Pros pills that flip the same
// store flags as the filter sheet's checkboxes, directly from the map
// (Scott 2026-07-10). Accented = category visible on the map.
export function EntityTypeToggles() {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const showActivities = useMapStore((s) => s.filters.showActivities);
  const showProOfferings = useMapStore((s) => s.filters.showProOfferings);
  const toggleShowActivities = useMapStore((s) => s.toggleShowActivities);
  const toggleShowProOfferings = useMapStore((s) => s.toggleShowProOfferings);

  return (
    <>
      <Pressable
        style={[styles.entityChip, showActivities && styles.entityChipOn]}
        onPress={toggleShowActivities}
        hitSlop={8}
        accessibilityRole="switch"
        accessibilityState={{ checked: showActivities }}
      >
        <Text style={[styles.entityChipText, showActivities && styles.entityChipTextOn]}>
          {t('map.typeActivities', { defaultValue: 'Utilisateurs' })}
        </Text>
      </Pressable>
      <Pressable
        style={[styles.entityChip, showProOfferings && styles.entityChipOn]}
        onPress={toggleShowProOfferings}
        hitSlop={8}
        accessibilityRole="switch"
        accessibilityState={{ checked: showProOfferings }}
      >
        <Text style={[styles.entityChipText, showProOfferings && styles.entityChipTextOn]}>
          {t('map.typePros', { defaultValue: 'Pros' })}
        </Text>
      </Pressable>
    </>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  button: {
    width: 40,
    height: 40,
    alignItems: 'center',
    justifyContent: 'center',
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
  entityChip: {
    height: 40,
    justifyContent: 'center',
    paddingHorizontal: spacing.md,
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
  entityChipOn: {
    borderColor: colors.cta,
  },
  entityChipText: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
    fontWeight: '700',
    letterSpacing: 0.3,
  },
  entityChipTextOn: {
    color: colors.cta,
  },
});
