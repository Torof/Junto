import { Pressable, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { Plus } from 'lucide-react-native';
import { colors, spacing, radius } from '@/constants/theme';
import { useCreateStore } from '@/store/create-store';

export function CreateButton() {
  const router = useRouter();
  const { resetForm } = useCreateStore();

  const handlePress = () => {
    resetForm();
    router.push('/(auth)/create/step1');
  };

  return (
    <Pressable style={styles.button} onPress={handlePress}>
      <Plus size={24} color={colors.textPrimary} strokeWidth={2.5} />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  button: {
    position: 'absolute',
    bottom: 140,
    right: spacing.md,
    backgroundColor: colors.cta,
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
