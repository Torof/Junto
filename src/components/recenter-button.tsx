import { Pressable, StyleSheet } from 'react-native';
import { LocateFixed } from 'lucide-react-native';
import { useTranslation } from 'react-i18next';
import { colors, spacing, radius } from '@/constants/theme';

interface RecenterButtonProps {
  onPress: () => void;
}

export function RecenterButton({ onPress }: RecenterButtonProps) {
  const { t } = useTranslation();
  return (
    <Pressable style={styles.button} onPress={onPress} accessibilityLabel={t('map.recenter')}>
      <LocateFixed size={22} color={colors.textPrimary} strokeWidth={2.2} />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  button: {
    position: 'absolute',
    bottom: 40,
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
