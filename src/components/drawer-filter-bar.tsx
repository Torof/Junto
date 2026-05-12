import { useMemo, useState } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import Slider from '@react-native-community/slider';
import { SlidersHorizontal } from 'lucide-react-native';
import { spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { useMapStore } from '@/store/map-store';
import { FilterSheet } from './filter-sheet';

export function DrawerFilterBar() {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const filters = useMapStore((s) => s.filters);
  const setRadiusKm = useMapStore((s) => s.setRadiusKm);
  const [showSheet, setShowSheet] = useState(false);

  const filtersActive =
    filters.sportKeys.length > 0 ||
    filters.dateMode !== 'all' ||
    filters.levelTiers.length > 0 ||
    filters.visibilities.length > 0 ||
    filters.radiusKm !== null;

  return (
    <>
      <View style={styles.bar}>
        <Pressable
          style={styles.filtersBtn}
          onPress={() => setShowSheet(true)}
          accessibilityLabel={t('map.filtersBtn')}
          hitSlop={6}
        >
          <SlidersHorizontal size={18} color={colors.textPrimary} strokeWidth={2.2} />
          {filtersActive && <View style={styles.activeDot} />}
        </Pressable>

        <View style={styles.sliderWrap}>
          <View style={styles.sliderLabelsRow}>
            <Text style={styles.sliderValue}>
              {filters.radiusKm !== null ? `${filters.radiusKm} km` : t('map.radiusOff')}
            </Text>
            <Text style={styles.sliderBound}>200 km</Text>
          </View>
          <Slider
            style={styles.slider}
            minimumValue={0}
            maximumValue={200}
            step={5}
            value={filters.radiusKm ?? 0}
            onValueChange={(v) => setRadiusKm(v === 0 ? null : v)}
            minimumTrackTintColor={colors.cta}
            maximumTrackTintColor={colors.borderMuted}
            thumbTintColor={colors.cta}
          />
        </View>
      </View>

      <FilterSheet visible={showSheet} onClose={() => setShowSheet(false)} showSortTab />
    </>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  bar: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    paddingTop: spacing.xs,
    paddingBottom: spacing.md,
    marginBottom: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderMuted,
    // Opaque background so activity rows scrolling underneath the
    // sticky header (stickyHeaderIndices in activities-bottom-sheet)
    // don't bleed through.
    backgroundColor: colors.surfaceAlt,
  },
  sliderWrap: {
    flex: 1,
    flexDirection: 'column',
    justifyContent: 'center',
  },
  sliderLabelsRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'baseline',
    marginBottom: -4,
  },
  sliderBound: {
    color: colors.textMuted,
    fontSize: 10,
    fontWeight: '500',
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  sliderValue: {
    color: colors.textSecondary,
    fontSize: 10,
    fontWeight: '600',
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  slider: {
    width: '100%',
    height: 28,
  },
  filtersBtn: {
    width: 36,
    height: 36,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.sm,
    backgroundColor: 'transparent',
  },
  activeDot: {
    position: 'absolute',
    top: 4,
    right: 4,
    width: 6,
    height: 6,
    borderRadius: radius.xs,
    backgroundColor: colors.cta,
  },
});
