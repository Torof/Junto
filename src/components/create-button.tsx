import { useMemo } from 'react';
import { Pressable, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { Plus } from 'lucide-react-native';
import { spacing, radius } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { useCreateStore } from '@/store/create-store';

export function CreateButton() {
  const router = useRouter();
  const { resetForm } = useCreateStore();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const handlePress = () => {
    resetForm();
    router.push('/(auth)/create/step1');
  };

  return (
    <Pressable style={styles.button} onPress={handlePress} hitSlop={8} accessibilityLabel="Create activity">
      <Plus size={24} color={colors.textPrimary} strokeWidth={2.5} />
    </Pressable>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  button: {
    position: 'absolute',
    bottom: 240,
    right: spacing.md,
    backgroundColor: colors.cta,
    borderRadius: radius.full,
    width: 40,
    height: 40,
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 10,
    borderWidth: 1,
    borderColor: colors.border,
  },
});
