import { useMemo } from 'react';
import { View, Text, Pressable, ScrollView, Modal, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
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

  return (
    <Modal visible={visible} animationType="slide" transparent>
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
