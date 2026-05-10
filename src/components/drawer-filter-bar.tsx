import { useMemo, useState } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { useMapStore } from '@/store/map-store';
import { FilterSheet } from './filter-sheet';
import { SportPickerSheet } from './sport-picker-sheet';

type Picker = 'sport' | 'sheet' | null;

export function DrawerFilterBar() {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const filters = useMapStore((s) => s.filters);
  const [picker, setPicker] = useState<Picker>(null);

  const sportActive = filters.sportKeys.length > 0;
  const otherActive =
    filters.dateMode !== 'all' ||
    filters.levelTiers.length > 0 ||
    filters.visibilities.length > 0;

  return (
    <>
      <View style={styles.bar}>
        <CategoryChip label={t('map.sportLabel')}        active={sportActive} onPress={() => setPicker('sport')} styles={styles} />
        <CategoryChip label={t('map.otherFiltersLabel')} active={otherActive} onPress={() => setPicker('sheet')} styles={styles} />
      </View>

      <SportPickerSheet visible={picker === 'sport'} onClose={() => setPicker(null)} />
      <FilterSheet visible={picker === 'sheet'} onClose={() => setPicker(null)} />
    </>
  );
}

function CategoryChip({
  label, active, onPress, styles,
}: {
  label: string;
  active: boolean;
  onPress: () => void;
  styles: ReturnType<typeof createStyles>;
}) {
  return (
    <Pressable style={styles.chip} onPress={onPress}>
      <Text style={styles.chipText} numberOfLines={1}>{label}</Text>
      {active && <View style={styles.activeDot} />}
    </Pressable>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  bar: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs + 2,
    paddingVertical: spacing.sm,
    marginBottom: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderMuted,
  },
  chip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.sm,
    paddingHorizontal: spacing.sm + 2,
    paddingVertical: spacing.xs + 2,
    backgroundColor: 'transparent',
  },
  chipText: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
    fontWeight: '500',
  },
  activeDot: {
    width: 6,
    height: 6,
    borderRadius: radius.xs,
    backgroundColor: colors.cta,
  },
});
