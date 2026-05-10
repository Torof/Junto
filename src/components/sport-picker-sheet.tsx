import { useMemo } from 'react';
import { View, Text, Pressable, ScrollView, Modal, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import { Check } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { useMapStore } from '@/store/map-store';
import { supabase } from '@/services/supabase';
import { getSportIcon } from '@/constants/sport-icons';

// Shared multi-select sport picker, bound to useMapStore.filters.sportKeys.
// Used by drawer-filter-bar and filter-sheet so the modal stays one piece.

interface Props {
  visible: boolean;
  onClose: () => void;
}

export function SportPickerSheet({ visible, onClose }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
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

  // Sort by translated name (alphabetical in user's locale).
  const sortedSports = useMemo(() => {
    if (!sports) return [];
    return [...sports].sort((a, b) => {
      const aName = t(`sports.${a.key}`, { defaultValue: a.key });
      const bName = t(`sports.${b.key}`, { defaultValue: b.key });
      return aName.localeCompare(bName);
    });
  }, [sports, t]);

  return (
    <Modal visible={visible} animationType="slide" transparent>
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Pressable style={styles.sheet} onPress={() => {}}>
          <View style={styles.handle} />
          <Text style={styles.sheetTitle}>{t('map.sportLabel')}</Text>

          <ScrollView style={styles.list} contentContainerStyle={styles.listContent}>
            {sortedSports.map((s) => {
              const isSelected = filters.sportKeys.includes(s.key);
              return (
                <Pressable
                  key={s.key}
                  style={styles.row}
                  onPress={() => toggleSportFilter(s.key)}
                >
                  <Text style={styles.rowEmoji}>{getSportIcon(s.key)}</Text>
                  <Text style={[styles.rowLabel, isSelected && styles.rowLabelActive]} numberOfLines={1}>
                    {t(`sports.${s.key}`, { defaultValue: s.key })}
                  </Text>
                  {isSelected && <Check size={18} color={colors.cta} strokeWidth={2.4} />}
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
  list: { maxHeight: '80%' },
  listContent: { paddingBottom: spacing.md },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    paddingVertical: spacing.sm + 2,
    paddingHorizontal: spacing.xs,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderMuted,
  },
  rowEmoji: {
    fontSize: 20,
    width: 28,
    textAlign: 'center',
  },
  rowLabel: {
    flex: 1,
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    fontWeight: '500',
  },
  rowLabelActive: {
    color: colors.cta,
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
