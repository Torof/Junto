import { forwardRef, type ComponentRef, type ReactNode } from 'react';
import { type ScrollViewProps } from 'react-native';
import Animated, { useAnimatedKeyboard, useAnimatedStyle } from 'react-native-reanimated';
import { spacing } from '@/constants/theme';

// Form scroll container that keeps the focused field clear of the keyboard.
//
// Built on reanimated's useAnimatedKeyboard — the SAME primitive as the chat
// docks (use-keyboard-dock-padding). This is deliberate: under RN 0.81 enforced
// edge-to-edge, BOTH KeyboardAvoidingView and react-native-keyboard-controller
// proved unreliable (saga 2026-06-10); reading the exact IME height off the OS
// window is the only approach that held. A bottom spacer animated to the
// keyboard height gives the scroll content enough room to bring any field —
// including the last one — above the IME.

interface Props extends ScrollViewProps {
  children: ReactNode;
  // Resting bottom padding (nav-bar inset etc.) that applies even keyboard-down.
  restBottom?: number;
}

export const KeyboardAwareScrollView = forwardRef<ComponentRef<typeof Animated.ScrollView>, Props>(
  function KeyboardAwareScrollView({ children, restBottom = 0, ...rest }, ref) {
    const keyboard = useAnimatedKeyboard({
      isStatusBarTranslucentAndroid: true,
      isNavigationBarTranslucentAndroid: true,
    });
    const spacerStyle = useAnimatedStyle(() => ({
      height: Math.max(
        keyboard.height.value > 0 ? keyboard.height.value + spacing.md : 0,
        restBottom,
      ),
    }));
    return (
      <Animated.ScrollView
        ref={ref}
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode="interactive"
        {...rest}
      >
        {children}
        <Animated.View style={spacerStyle} />
      </Animated.ScrollView>
    );
  },
);
