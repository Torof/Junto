import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { useMapStore } from '@/store/map-store';

export function FilterButton({ onPress }: { onPress: () => void }) {
  const { t } = useTranslation();
  const { filters } = useMapStore();
  const hasActiveFilter = filters.sportKey !== null || filters.dateRange !== 'all';

  return (
    <Pressable style={styles.button} onPress={onPress}>
      <Text style={styles.buttonText}>{t('map.filters')}</Text>
      {hasActiveFilter && <View style={styles.badge} />}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  button: {
    position: 'absolute',
    top: 56,
    left: spacing.md,
    backgroundColor: colors.background,
    borderRadius: radius.full,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    zIndex: 10,
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: 1,
    borderColor: colors.surface,
  },
  buttonText: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: 'bold',
  },
  badge: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: colors.cta,
    marginLeft: spacing.xs,
  },
});
