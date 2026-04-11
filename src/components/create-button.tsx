import { Pressable, Text, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
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
      <Text style={styles.icon}>+</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  button: {
    position: 'absolute',
    bottom: spacing.xl + 128,
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
  icon: {
    color: colors.textPrimary,
    fontSize: 22,
    fontWeight: 'bold',
    marginTop: -1,
  },
});
