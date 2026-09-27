import { forwardRef } from 'react';
import { Pressable, type PressableProps, type View } from 'react-native';

// Canon 2026-09: every tappable responds. Drop-in Pressable with a default
// pressed state (slight dim + shrink). Pass your own `style` as usual — the
// pressed transform is composed on top, including when `style` is the
// Pressable function form (audit 2026-09 M6: the old StyleProp signature
// silently crushed callers' own pressed styles); opt out with `noFeedback`.
interface Props extends PressableProps {
  noFeedback?: boolean;
}

export const PressableScale = forwardRef<View, Props>(function PressableScale(
  { style, noFeedback = false, ...rest },
  ref,
) {
  return (
    <Pressable
      ref={ref}
      accessibilityRole="button"
      {...rest}
      style={(state) => [
        typeof style === 'function' ? style(state) : style,
        !noFeedback && state.pressed && { opacity: 0.75, transform: [{ scale: 0.98 }] },
      ]}
    />
  );
});
