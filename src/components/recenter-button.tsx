import { useMemo } from 'react';
import { View, Pressable, StyleSheet } from 'react-native';
import { LocateFixed } from 'lucide-react-native';
import { useTranslation } from 'react-i18next';
import { spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

interface RecenterButtonProps {
  onPress: () => void;
}

export function RecenterButton({ onPress }: RecenterButtonProps) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  return (
    <Pressable style={styles.button} onPress={onPress} hitSlop={8} accessibilityLabel={t('map.recenter')}>
      {/* Blue halo behind the target icon — Google-Maps-style GPS
          dot association without recoloring the crosshair itself. */}
      <View style={styles.halo} />
      <LocateFixed size={24} color={colors.textPrimary} strokeWidth={2.2} />
    </Pressable>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  // Bottom-right, just above the create FAB. Same size + radius as
  // the FAB so they read as a uniform pair, only the fill changes.
  button: {
    position: 'absolute',
    bottom: 28 + 48 + 14,
    right: spacing.md,
    backgroundColor: colors.surface,
    borderRadius: 14,
    width: 48,
    height: 48,
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 10,
    borderWidth: 1,
    borderColor: colors.border,
    elevation: 4,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.15,
    shadowRadius: 4,
  },
  // Blue circle sits behind the LocateFixed icon. Slightly bigger
  // than the icon's outer ring so it reads as a halo, not a clip.
  halo: {
    position: 'absolute',
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: '#4285F4',
  },
});
