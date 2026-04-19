import { useMemo } from 'react';
import { View, Pressable, StyleSheet } from 'react-native';
import { SlidersHorizontal } from 'lucide-react-native';
import { useTranslation } from 'react-i18next';
import { spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import { useMapStore } from '@/store/map-store';
import type { AppColors } from '@/constants/colors';

export function FilterButton({ onPress }: { onPress: () => void }) {
  const { t } = useTranslation();
  const colors = useColors();
  const { filters } = useMapStore();
  const hasActiveFilter = filters.sportKeys.length > 0 || filters.dateMode !== 'all';
  const styles = useMemo(() => createStyles(colors), [colors]);

  return (
    <Pressable style={styles.button} onPress={onPress} hitSlop={8} accessibilityLabel={t('map.openFilters')}>
      <SlidersHorizontal size={22} color={colors.textPrimary} strokeWidth={2.2} />
      {hasActiveFilter && <View style={styles.badge} />}
    </Pressable>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  button: {
    position: 'absolute',
    bottom: 90,
    right: spacing.md,
    backgroundColor: colors.surface,
    borderRadius: radius.full,
    width: 40,
    height: 40,
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 10,
    borderWidth: 1,
    borderColor: colors.surface,
  },
  badge: {
    position: 'absolute',
    top: 6,
    right: 6,
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: colors.cta,
  },
});
