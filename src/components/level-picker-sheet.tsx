import { useMemo } from 'react';
import { View, Text, Pressable, Modal, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { Check } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { useMapStore, type LevelTier } from '@/store/map-store';

const LEVEL_TIERS: { tier: LevelTier; key: string }[] = [
  { tier: 'Débutant', key: 'beginner' },
  { tier: 'Intermédiaire', key: 'intermediate' },
  { tier: 'Avancé', key: 'advanced' },
  { tier: 'Expert', key: 'expert' },
];

interface Props {
  visible: boolean;
  onClose: () => void;
}

export function LevelPickerSheet({ visible, onClose }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const filters = useMapStore((s) => s.filters);
  const toggleLevelTier = useMapStore((s) => s.toggleLevelTier);

  return (
    <Modal visible={visible} animationType="slide" transparent>
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Pressable style={styles.sheet} onPress={() => {}}>
          <View style={styles.handle} />
          <Text style={styles.sheetTitle}>{t('map.levelLabel')}</Text>

          <View style={styles.list}>
            {LEVEL_TIERS.map(({ tier, key }) => {
              const isSelected = filters.levelTiers.includes(tier);
              return (
                <Pressable
                  key={tier}
                  style={styles.row}
                  onPress={() => toggleLevelTier(tier)}
                >
                  <Text style={[styles.rowLabel, isSelected && styles.rowLabelActive]} numberOfLines={1}>
                    {t(`map.levelTier.${key}`)}
                  </Text>
                  {isSelected && <Check size={18} color={colors.cta} strokeWidth={2.4} />}
                </Pressable>
              );
            })}
          </View>

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
  list: { paddingBottom: spacing.md },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: spacing.sm + 2,
    paddingHorizontal: spacing.xs,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderMuted,
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
