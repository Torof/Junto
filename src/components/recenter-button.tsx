import { Pressable, StyleSheet } from 'react-native';
import { LocateFixed } from 'lucide-react-native';
import { colors, spacing, radius } from '@/constants/theme';

interface RecenterButtonProps {
  onPress: () => void;
}

export function RecenterButton({ onPress }: RecenterButtonProps) {
  return (
    <Pressable style={styles.button} onPress={onPress}>
      <LocateFixed size={22} color="#4285F4" strokeWidth={2.2} />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  button: {
    position: 'absolute',
    bottom: 40,
    right: spacing.md,
    backgroundColor: '#e5e5e5',
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
