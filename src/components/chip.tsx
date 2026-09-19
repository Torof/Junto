import { memo, type ReactNode } from 'react';
import { Text, View, StyleSheet } from 'react-native';
import { fontSizes, radius, spacing } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import { PressableScale } from '@/components/pressable-scale';

// Canon 2026-09 — the ONE pill grammar (replaces 82 ad-hoc styles):
//   idle     → soft tint: `color + '1A'` background, colored 600 text, no border
//   selected → solid fill: `color` background, onCta 700 text
// `color` defaults to the accent; pass a sport/universe color where relevant.
interface ChipProps {
  label: string;
  icon?: ReactNode;
  color?: string;
  selected?: boolean;
  onPress?: () => void;
  disabled?: boolean;
  small?: boolean;
}

export const Chip = memo(function Chip({
  label, icon, color, selected = false, onPress, disabled = false, small = false,
}: ChipProps) {
  const colors = useColors();
  const c = color ?? colors.cta;
  const body = (
    <View
      style={[
        styles.base,
        small && styles.small,
        { backgroundColor: selected ? c : c + '1A' },
        disabled && styles.disabled,
      ]}
    >
      {icon}
      <Text
        style={[
          styles.text,
          small && styles.textSmall,
          { color: selected ? colors.onCta : c, fontWeight: selected ? '700' : '600' },
        ]}
        numberOfLines={1}
      >
        {label}
      </Text>
    </View>
  );
  if (!onPress) return body;
  return (
    <PressableScale onPress={onPress} disabled={disabled} hitSlop={4}>
      {body}
    </PressableScale>
  );
});

const styles = StyleSheet.create({
  base: {
    flexDirection: 'row', alignItems: 'center', gap: 5,
    borderRadius: radius.full,
    paddingHorizontal: spacing.sm + 4, paddingVertical: 7,
    alignSelf: 'flex-start',
  },
  small: { paddingHorizontal: spacing.sm + 2, paddingVertical: 5, gap: 4 },
  text: { fontSize: fontSizes.sm - 1 },
  textSmall: { fontSize: fontSizes.xs },
  disabled: { opacity: 0.45 },
});
