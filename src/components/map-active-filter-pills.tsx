import { useMemo } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { X } from 'lucide-react-native';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { useMapStore } from '@/store/map-store';

interface PillEntry {
  id: string;
  label: string;
  clear: () => void;
}

export function MapActiveFilterPills() {
  const { t, i18n } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const filters = useMapStore((s) => s.filters);
  const setDateMode = useMapStore((s) => s.setDateMode);
  const toggleSportFilter = useMapStore((s) => s.toggleSportFilter);
  const toggleLevelTier = useMapStore((s) => s.toggleLevelTier);
  const toggleVisibility = useMapStore((s) => s.toggleVisibility);

  const pills: PillEntry[] = [];

  filters.sportKeys.forEach((key) => {
    pills.push({
      id: `sport-${key}`,
      label: t(`sports.${key}`, { defaultValue: key }),
      clear: () => toggleSportFilter(key),
    });
  });

  if (filters.dateMode !== 'all') {
    let dateLabel = '';
    if (filters.dateMode === 'today') dateLabel = t('map.date.today');
    else if (filters.dateMode === 'week') dateLabel = t('map.date.week');
    else if (filters.dateMode === 'date' && filters.specificDate) {
      dateLabel = dayjs(filters.specificDate).locale(i18n.language).format('D MMM');
    } else if (filters.dateMode === 'range' && filters.rangeFrom && filters.rangeTo) {
      dateLabel = `${dayjs(filters.rangeFrom).locale(i18n.language).format('D MMM')} → ${dayjs(filters.rangeTo).locale(i18n.language).format('D MMM')}`;
    }
    if (dateLabel) {
      pills.push({ id: 'date', label: dateLabel, clear: () => setDateMode('all') });
    }
  }

  filters.levelTiers.forEach((tier) => {
    pills.push({ id: `level-${tier}`, label: tier, clear: () => toggleLevelTier(tier) });
  });

  filters.visibilities.forEach((v) => {
    pills.push({ id: `vis-${v}`, label: t(`map.visibility.${v}`), clear: () => toggleVisibility(v) });
  });

  if (pills.length === 0) return null;

  return (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      contentContainerStyle={styles.row}
    >
      {pills.map((pill) => (
        <View key={pill.id} style={styles.pill}>
          <Text style={styles.pillLabel} numberOfLines={1}>{pill.label}</Text>
          <Pressable onPress={pill.clear} hitSlop={6} style={styles.clearBtn}>
            <X size={12} color={colors.textPrimary} strokeWidth={2.4} />
          </Pressable>
        </View>
      ))}
    </ScrollView>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs + 2,
    paddingHorizontal: spacing.sm,
    paddingVertical: spacing.xs,
  },
  pill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    backgroundColor: colors.background,
    borderWidth: 1,
    borderColor: colors.borderStrong,
    borderRadius: radius.sm,
    paddingLeft: spacing.sm + 2,
    paddingRight: spacing.xs + 2,
    paddingVertical: spacing.xs + 1,
  },
  pillLabel: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '600',
  },
  clearBtn: {
    width: 16,
    height: 16,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
