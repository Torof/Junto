import { useMemo } from 'react';
import { Pressable, StyleSheet } from 'react-native';
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
      {/* Google-Maps-style GPS blue. The crosshair itself carries the
          'my position' association — no halo needed. */}
      <LocateFixed size={24} color="#4285F4" strokeWidth={2.4} />
    </Pressable>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  // Bottom-right, TOP of the FAB stack (create → bell → recenter). It's the
  // intermittent one (contextual, only when off-center), so it lives at the
  // top: appearing/disappearing leaves no hole in the stack. Same size +
  // radius as the FAB so they read as a uniform family.
  button: {
    position: 'absolute',
    bottom: 28 + (48 + 14) * 2,
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
});
