import { Pressable, Text, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { useMapStore } from '@/store/map-store';

export function ViewToggle() {
  const { t } = useTranslation();
  const { viewMode, toggleViewMode } = useMapStore();

  return (
    <Pressable style={styles.button} onPress={toggleViewMode}>
      <Text style={styles.text}>
        {viewMode === 'map' ? t('map.list') : t('map.map')}
      </Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  button: {
    position: 'absolute',
    top: 56,
    right: spacing.md,
    backgroundColor: colors.background + 'E6',
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    borderRadius: radius.full,
    zIndex: 10,
  },
  text: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: 'bold',
  },
});
