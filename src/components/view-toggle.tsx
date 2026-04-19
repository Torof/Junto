import { Pressable, StyleSheet } from 'react-native';
import { Search, Map } from 'lucide-react-native';
import { colors, spacing, radius } from '@/constants/theme';
import { useMapStore } from '@/store/map-store';

export function ViewToggle() {
  const { viewMode, toggleViewMode } = useMapStore();
  const IconComponent = viewMode === 'map' ? Search : Map;

  return (
    <Pressable style={styles.button} onPress={toggleViewMode}>
      <IconComponent size={22} color={colors.background} strokeWidth={2.2} />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  button: {
    position: 'absolute',
    bottom: spacing.xl + 32,
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
});
