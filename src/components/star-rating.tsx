import { View, Pressable, StyleSheet } from 'react-native';
import { Star } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { spacing } from '@/constants/theme';

// Display row — stars fill up to round(rating). The numeric average is
// always shown next to it by callers, so star precision stays coarse.
export function StarRating({ rating, size = 14 }: { rating: number; size?: number }) {
  const colors = useColors();
  const filled = Math.round(rating);
  return (
    <View style={styles.row}>
      {[1, 2, 3, 4, 5].map((i) => (
        <Star
          key={i}
          size={size}
          color={colors.star}
          fill={i <= filled ? colors.star : 'transparent'}
          strokeWidth={1.8}
        />
      ))}
    </View>
  );
}

// Interactive picker for the composer — tap a star to set the rating.
export function StarPicker({
  value,
  onChange,
  size = 34,
}: {
  value: number;
  onChange: (rating: number) => void;
  size?: number;
}) {
  const colors = useColors();
  return (
    <View style={styles.pickerRow}>
      {[1, 2, 3, 4, 5].map((i) => (
        <Pressable
          key={i}
          onPress={() => onChange(i)}
          hitSlop={6}
          accessibilityRole="button"
          accessibilityLabel={`${i}/5`}
        >
          <Star
            size={size}
            color={colors.star}
            fill={i <= value ? colors.star : 'transparent'}
            strokeWidth={1.8}
          />
        </Pressable>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', gap: 2 },
  pickerRow: { flexDirection: 'row', gap: spacing.sm, justifyContent: 'center' },
});
