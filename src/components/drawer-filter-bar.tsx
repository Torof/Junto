import { useMemo, useState } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import Slider from '@react-native-community/slider';
import { spacing } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { useMapStore } from '@/store/map-store';
import { FilterSheet } from './filter-sheet';
import { FilterButton } from './filter-bar';

export function DrawerFilterBar() {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const filters = useMapStore((s) => s.filters);
  const setRadiusKm = useMapStore((s) => s.setRadiusKm);
  const [showSheet, setShowSheet] = useState(false);

  return (
    <>
      <View style={styles.bar}>
        {/* Same "Filtres" pill as the map (Scott 2026-06-11) — the old
            bare square + icon read as ambiguous. */}
        <FilterButton onPress={() => setShowSheet(true)} />

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
});
