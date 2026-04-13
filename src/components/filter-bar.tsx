import { View, Pressable, Text, StyleSheet } from 'react-native';
import { colors, spacing, radius } from '@/constants/theme';
import { useMapStore } from '@/store/map-store';

export function FilterButton({ onPress }: { onPress: () => void }) {
  const { filters } = useMapStore();
  const hasActiveFilter = filters.sportKeys.length > 0 || filters.dateMode !== 'all';

  return (
    <Pressable style={styles.button} onPress={onPress}>
      <Text style={styles.icon}>▼</Text>
      {hasActiveFilter && <View style={styles.badge} />}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  button: {
    position: 'absolute',
    bottom: spacing.xl + 80,
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
  icon: {
    fontSize: 18,
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
