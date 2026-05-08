import { useMemo, useState } from 'react';
import { View, Text, Pressable, ScrollView, Modal, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import { X } from 'lucide-react-native';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { useMapStore, type LevelTier, type VisibilityFilter } from '@/store/map-store';
import { supabase } from '@/services/supabase';
import { getSportIcon } from '@/constants/sport-icons';
import { FilterSheet } from './filter-sheet';

type Picker = 'sport' | 'sheet' | null;

export function MapFilterChips() {
  const { t, i18n } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const filters = useMapStore((s) => s.filters);
  const setDateMode = useMapStore((s) => s.setDateMode);
  const toggleSportFilter = useMapStore((s) => s.toggleSportFilter);
  const toggleLevelTier = useMapStore((s) => s.toggleLevelTier);
  const toggleVisibility = useMapStore((s) => s.toggleVisibility);

  const [picker, setPicker] = useState<Picker>(null);

  const sportActive = filters.sportKeys.length > 0;
  const dateActive = filters.dateMode !== 'all';
  const levelActive = filters.levelTiers.length > 0;
  const visActive = filters.visibilities.length > 0;

  const sportLabel = !sportActive
    ? t('map.sportLabel')
    : filters.sportKeys.length === 1
      ? t(`sports.${filters.sportKeys[0]}`, { defaultValue: filters.sportKeys[0] ?? '' })
      : `${t('map.sportLabel')} · ${filters.sportKeys.length}`;

  const dateLabel = (() => {
    if (!dateActive) return t('map.dateLabel');
    if (filters.dateMode === 'today') return t('map.date.today');
    if (filters.dateMode === 'week') return t('map.date.week');
    if (filters.dateMode === 'date' && filters.specificDate) {
      return dayjs(filters.specificDate).locale(i18n.language).format('D MMM');
    }
    if (filters.dateMode === 'range' && filters.rangeFrom && filters.rangeTo) {
      return `${dayjs(filters.rangeFrom).locale(i18n.language).format('D MMM')} → ${dayjs(filters.rangeTo).locale(i18n.language).format('D MMM')}`;
    }
    return t('map.dateLabel');
  })();

  const levelLabel = !levelActive
    ? t('map.levelLabel')
    : filters.levelTiers.length === 1
      ? filters.levelTiers[0]!
      : `${t('map.levelLabel')} · ${filters.levelTiers.length}`;

  const visLabel = !visActive
    ? t('map.visibilityLabel')
    : filters.visibilities.length === 1
      ? t(`map.visibility.${filters.visibilities[0]}`)
      : `${t('map.visibilityLabel')} · ${filters.visibilities.length}`;

  const clearSport = () => filters.sportKeys.slice().forEach((k) => toggleSportFilter(k));
  const clearDate = () => setDateMode('all');
  const clearLevel = () => filters.levelTiers.slice().forEach((tier: LevelTier) => toggleLevelTier(tier));
  const clearVis = () => filters.visibilities.slice().forEach((v: VisibilityFilter) => toggleVisibility(v));

  return (
    <>
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.row}
      >
        <Chip label={sportLabel} active={sportActive} onPress={() => setPicker('sport')} onClear={clearSport} styles={styles} />
        <Chip label={dateLabel}  active={dateActive}  onPress={() => setPicker('sheet')} onClear={clearDate}  styles={styles} />
        <Chip label={levelLabel} active={levelActive} onPress={() => setPicker('sheet')} onClear={clearLevel} styles={styles} />
        <Chip label={visLabel}   active={visActive}   onPress={() => setPicker('sheet')} onClear={clearVis}   styles={styles} />
      </ScrollView>

      {picker === 'sport' && <SportPickerModal onClose={() => setPicker(null)} styles={styles} />}
      <FilterSheet visible={picker === 'sheet'} onClose={() => setPicker(null)} />
    </>
  );
}

function Chip({
  label, active, onPress, onClear, styles,
}: {
  label: string;
  active: boolean;
  onPress: () => void;
  onClear: () => void;
  styles: ReturnType<typeof createStyles>;
}) {
  return (
    <Pressable style={[styles.chip, active && styles.chipActive]} onPress={onPress}>
      <Text style={[styles.chipText, active && styles.chipTextActive]} numberOfLines={1}>
        {label}
      </Text>
      {active && (
        <Pressable
          onPress={(e) => { e.stopPropagation(); onClear(); }}
          hitSlop={6}
          style={styles.clearBtn}
        >
          <X size={12} color="#FFFFFF" strokeWidth={2.5} />
        </Pressable>
      )}
    </Pressable>
  );
}

function SportPickerModal({
  onClose, styles,
}: {
  onClose: () => void;
  styles: ReturnType<typeof createStyles>;
}) {
  const { t } = useTranslation();
  const filters = useMapStore((s) => s.filters);
  const toggleSportFilter = useMapStore((s) => s.toggleSportFilter);

  const { data: sports } = useQuery({
    queryKey: ['sports'],
    queryFn: async () => {
      const { data, error } = await supabase.from('sports').select('key, category').order('key');
      if (error) throw error;
      return data;
    },
  });

  return (
    <Modal visible animationType="slide" transparent>
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Pressable style={styles.sheet} onPress={() => {}}>
          <View style={styles.handle} />
          <Text style={styles.sheetTitle}>{t('map.sportLabel')}</Text>

          <ScrollView contentContainerStyle={styles.sportGrid}>
            {sports?.map((s: { key: string; category: string }) => {
              const isSelected = filters.sportKeys.includes(s.key);
              return (
                <Pressable
                  key={s.key}
                  style={[styles.sportItem, isSelected && styles.sportItemActive]}
                  onPress={() => toggleSportFilter(s.key)}
                >
                  <Text style={styles.sportEmoji}>{getSportIcon(s.key)}</Text>
                  <Text style={[styles.sportItemLabel, isSelected && styles.sportItemLabelActive]} numberOfLines={1}>
                    {t(`sports.${s.key}`, { defaultValue: s.key })}
                  </Text>
                </Pressable>
              );
            })}
          </ScrollView>

          <View style={styles.applyContainer}>
            <Pressable style={styles.applyButton} onPress={onClose}>
              <Text style={styles.applyText}>{t('map.apply')}</Text>
            </Pressable>
          </View>
        </Pressable>
      </Pressable>
    </Modal>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs + 2,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
  },

  // Chip — same brutalist primitive used elsewhere; with optional trailing X
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
  chipActive: {
    backgroundColor: colors.cta,
    borderColor: colors.cta,
  },
  chipText: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
    fontWeight: '500',
  },
  chipTextActive: {
    color: '#FFFFFF',
    fontWeight: '700',
  },
  clearBtn: {
    width: 16,
    height: 16,
    alignItems: 'center',
    justifyContent: 'center',
    marginLeft: 2,
  },

  // Sport picker modal
  backdrop: {
    flex: 1,
    backgroundColor: colors.overlay,
    justifyContent: 'flex-end',
  },
  sheet: {
    backgroundColor: colors.background,
    borderTopLeftRadius: radius.lg,
    borderTopRightRadius: radius.lg,
    padding: spacing.md,
    paddingBottom: spacing.xl + 16,
    maxHeight: '70%',
  },
  handle: {
    width: 40,
    height: 4,
    borderRadius: 2,
    backgroundColor: colors.textSecondary,
    alignSelf: 'center',
    marginBottom: spacing.md,
    opacity: 0.4,
  },
  sheetTitle: {
    color: colors.textPrimary,
    fontSize: fontSizes.lg,
    fontWeight: 'bold',
    marginBottom: spacing.md,
  },
  sportGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.xs + 2,
    paddingBottom: spacing.md,
  },
  sportItem: {
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
  sportItemActive: {
    backgroundColor: colors.cta,
    borderColor: colors.cta,
  },
  sportEmoji: {
    fontSize: 16,
  },
  sportItemLabel: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
    fontWeight: '500',
  },
  sportItemLabelActive: {
    color: '#FFFFFF',
    fontWeight: '700',
  },
  applyContainer: {
    marginTop: spacing.md,
    paddingTop: spacing.md,
    borderTopWidth: 1,
    borderTopColor: colors.borderMuted,
  },
  applyButton: {
    backgroundColor: colors.cta,
    borderRadius: radius.sm,
    paddingVertical: spacing.sm + 2,
    alignItems: 'center',
  },
  applyText: {
    color: '#FFFFFF',
    fontSize: fontSizes.md,
    fontWeight: '700',
  },
});
