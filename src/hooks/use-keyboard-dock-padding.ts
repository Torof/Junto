import { useAnimatedKeyboard, useAnimatedStyle } from 'react-native-reanimated';
import { spacing } from '@/constants/theme';

// Animated bottom padding for chat input docks. Reads the IME inset
// straight from the OS window via reanimated's useAnimatedKeyboard —
// exact height, animated in sync with the keyboard — with the caller's
// resting padding (nav-bar inset) as the floor when the keyboard is
// down. Replaces KeyboardAvoidingView for these screens: both the RN
// and keyboard-controller implementations proved unreliable under
// RN 0.81 enforced edge-to-edge (2026-06-10).
export function useKeyboardDockPadding(restPadding: number) {
  const keyboard = useAnimatedKeyboard({
    isStatusBarTranslucentAndroid: true,
    isNavigationBarTranslucentAndroid: true,
  });

  return useAnimatedStyle(() => ({
    paddingBottom: Math.max(keyboard.height.value + spacing.sm, restPadding),
  }));
}
