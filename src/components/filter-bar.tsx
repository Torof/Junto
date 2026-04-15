import { View, Pressable, StyleSheet } from 'react-native';
import { SlidersHorizontal } from 'lucide-react-native';
import { colors, spacing, radius } from '@/constants/theme';
import { useMapStore } from '@/store/map-store';

export function FilterButton({ onPress }: { onPress: () => void }) {
  const { filters } = useMapStore();
  const hasActiveFilter = filters.sportKeys.length > 0 || filters.dateMode !== 'all';

  return (
    <Pressable style={styles.button} onPress={onPress}>
      <SlidersHorizontal size={22} color={colors.background} strokeWidth={2.2} />
      {hasActiveFilter && <View style={styles.badge} />}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  button: {
    position: 'absolute',
    bottom: 90,
    right: spacing.md,
    backgroundColor: '#e5e5e5',
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
