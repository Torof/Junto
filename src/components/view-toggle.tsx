import { Pressable, Text, StyleSheet } from 'react-native';
import { colors, spacing, radius } from '@/constants/theme';
import { useMapStore } from '@/store/map-store';

export function ViewToggle() {
  const { viewMode, toggleViewMode } = useMapStore();

  return (
    <Pressable style={styles.button} onPress={toggleViewMode}>
      <Text style={styles.icon}>{viewMode === 'map' ? '☰' : '🗺'}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  button: {
    position: 'absolute',
    bottom: spacing.xl + 32,
    right: spacing.md,
    backgroundColor: colors.background,
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
});
