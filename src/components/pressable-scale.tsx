import { forwardRef } from 'react';
import { Pressable, type PressableProps, type View, type StyleProp, type ViewStyle } from 'react-native';

// Canon 2026-09: every tappable responds. Drop-in Pressable with a default
// pressed state (slight dim + shrink). Pass your own `style` as usual — the
// pressed transform is composed on top; opt out with `noFeedback`.
interface Props extends PressableProps {
  style?: StyleProp<ViewStyle>;
  noFeedback?: boolean;
}

export const PressableScale = forwardRef<View, Props>(function PressableScale(
  { style, noFeedback = false, ...rest },
  ref,
) {
  return (
    <Pressable
      ref={ref}
      {...rest}
      style={({ pressed }) => [
        style,
        !noFeedback && pressed && { opacity: 0.75, transform: [{ scale: 0.98 }] },
      ]}
    />
  );
});
