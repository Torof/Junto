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
    width: 52,
    height: 52,
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 10,
    elevation: 4,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 4,
  },
  icon: {
    color: colors.textPrimary,
    fontSize: 28,
    fontWeight: 'bold',
    marginTop: -2,
  },
});
