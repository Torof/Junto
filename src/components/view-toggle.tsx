import { View, Pressable, Text, StyleSheet } from 'react-native';
import { colors, spacing, radius } from '@/constants/theme';
import { useMapStore } from '@/store/map-store';

export function ViewToggle() {
  const { viewMode, setViewMode } = useMapStore();

  return (
    <View style={styles.container}>
      <Pressable
        style={[styles.segment, viewMode === 'map' && styles.segmentActive]}
        onPress={() => setViewMode('map')}
      >
        <Text style={[styles.icon, viewMode === 'map' && styles.iconActive]}>🗺</Text>
      </Pressable>
      <Pressable
        style={[styles.segment, viewMode === 'list' && styles.segmentActive]}
        onPress={() => setViewMode('list')}
      >
        <Text style={[styles.icon, viewMode === 'list' && styles.iconActive]}>☰</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    top: 56,
    right: spacing.md,
    flexDirection: 'row',
    backgroundColor: colors.background,
    borderRadius: radius.full,
    zIndex: 10,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: colors.surface,
  },
  segment: {
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
  },
  segmentActive: {
    backgroundColor: colors.cta,
  },
  icon: {
    fontSize: 16,
    opacity: 0.5,
  },
  iconActive: {
    opacity: 1,
  },
});
