import { View, Text, Pressable, ScrollView, StyleSheet, Modal } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { useMapStore } from '@/store/map-store';
import { supabase } from '@/services/supabase';

const DATE_OPTIONS = ['all', 'today', 'week'] as const;

interface FilterSheetProps {
  visible: boolean;
  onClose: () => void;
}

export function FilterSheet({ visible, onClose }: FilterSheetProps) {
  const { t } = useTranslation();
  const { filters, setSportFilter, setDateFilter, resetFilters } = useMapStore();

  const { data: sports } = useQuery({
    queryKey: ['sports'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('sports')
        .select('id, key, display_order')
        .order('display_order');
      if (error) throw error;
      return data;
    },
  });

  return (
    <Modal visible={visible} animationType="slide" transparent>
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Pressable style={styles.sheet} onPress={() => {}}>
          <View style={styles.handle} />

          <View style={styles.header}>
            <Text style={styles.title}>{t('map.filters')}</Text>
            <Pressable onPress={() => { resetFilters(); onClose(); }}>
              <Text style={styles.reset}>{t('map.resetFilters')}</Text>
            </Pressable>
          </View>

          <Text style={styles.sectionTitle}>{t('map.dateLabel')}</Text>
          <View style={styles.chipRow}>
            {DATE_OPTIONS.map((option) => (
              <Pressable
                key={option}
                style={[styles.chip, filters.dateRange === option && styles.chipActive]}
                onPress={() => setDateFilter(option)}
              >
                <Text style={[styles.chipText, filters.dateRange === option && styles.chipTextActive]}>
                  {t(`map.date.${option}`)}
                </Text>
              </Pressable>
            ))}
          </View>

          <Text style={styles.sectionTitle}>{t('map.sportLabel')}</Text>
          <ScrollView style={styles.sportList} showsVerticalScrollIndicator={false}>
            <View style={styles.chipRow}>
              {(sports ?? []).map((sport) => (
                <Pressable
                  key={sport.id}
                  style={[styles.chip, filters.sportKey === sport.key && styles.chipActive]}
                  onPress={() => setSportFilter(filters.sportKey === sport.key ? null : sport.key)}
                >
                  <Text style={[styles.chipText, filters.sportKey === sport.key && styles.chipTextActive]}>
                    {t(`sports.${sport.key}`, sport.key)}
                  </Text>
                </Pressable>
              ))}
            </View>
          </ScrollView>

          <Pressable style={styles.applyButton} onPress={onClose}>
            <Text style={styles.applyText}>{t('map.apply')}</Text>
          </Pressable>
        </Pressable>
      </Pressable>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.5)',
    justifyContent: 'flex-end',
  },
  sheet: {
    backgroundColor: colors.background,
    borderTopLeftRadius: radius.lg,
    borderTopRightRadius: radius.lg,
    padding: spacing.lg,
    paddingBottom: spacing.xl + 16,
    maxHeight: '70%',
  },
  handle: {
    width: 40,
    height: 4,
    borderRadius: 2,
    backgroundColor: colors.textSecondary,
    alignSelf: 'center',
    marginBottom: spacing.lg,
    opacity: 0.4,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: spacing.lg,
  },
  title: {
    color: colors.textPrimary,
    fontSize: fontSizes.lg,
    fontWeight: 'bold',
  },
  reset: {
    color: colors.cta,
    fontSize: fontSizes.sm,
  },
  sectionTitle: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    textTransform: 'uppercase',
    marginBottom: spacing.sm,
    marginTop: spacing.sm,
  },
  chipRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.sm,
    marginBottom: spacing.md,
  },
  chip: {
    backgroundColor: colors.surface,
    borderRadius: radius.full,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
  },
  chipActive: {
    backgroundColor: colors.cta,
  },
  chipText: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
  },
  chipTextActive: {
    color: colors.textPrimary,
    fontWeight: 'bold',
  },
  sportList: {
    maxHeight: 200,
  },
  applyButton: {
    backgroundColor: colors.cta,
    borderRadius: radius.md,
    paddingVertical: spacing.md,
    alignItems: 'center',
    marginTop: spacing.lg,
  },
  applyText: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    fontWeight: 'bold',
  },
});
