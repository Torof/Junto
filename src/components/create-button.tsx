import { useMemo } from 'react';
import { Pressable, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { Plus } from 'lucide-react-native';
import { spacing, radius } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { useCreateStore } from '@/store/create-store';

export function CreateButton() {
  const router = useRouter();
  const { t } = useTranslation();
  const { resetForm } = useCreateStore();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const handlePress = () => {
    resetForm();
    router.push('/(auth)/create/step1');
  };

  return (
    <Pressable
      style={styles.button}
      onPress={handlePress}
      hitSlop={8}
      accessibilityLabel={t('map.createActivityCta', { defaultValue: 'Create activity' })}
    >
      <Plus size={28} color={colors.textPrimary} strokeWidth={2.6} />
    </Pressable>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  // FAB — bottom-right, primary CTA. Bigger than the secondary
  // recenter button above so the eye reads the action hierarchy
  // (Scott 2026-06-10). Sits just above the bottom-sheet drawer's
  // 2% snap (drawer reaches ~14-18px depending on screen size); 28
  // gives an ~10px clearance.
  button: {
    position: 'absolute',
    bottom: 28,
    right: spacing.md,
    backgroundColor: colors.cta,
    borderRadius: radius.md,
    width: 52,
    height: 52,
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 10,
    borderWidth: 1,
    borderColor: colors.border,
    elevation: 6,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 3 },
    shadowOpacity: 0.25,
    shadowRadius: 6,
  },
});
