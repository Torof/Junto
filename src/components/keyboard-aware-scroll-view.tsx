import { forwardRef, useCallback, useRef, type ComponentRef, type ReactNode } from 'react';
import {
  Dimensions,
  ScrollView,
  TextInput,
  type NativeScrollEvent,
  type NativeSyntheticEvent,
  type ScrollViewProps,
} from 'react-native';
import Animated, {
  runOnJS,
  useAnimatedKeyboard,
  useAnimatedReaction,
  useAnimatedStyle,
} from 'react-native-reanimated';
import { spacing } from '@/constants/theme';

// Form scroll container that keeps the focused field clear of the keyboard.
//
// Built on reanimated's useAnimatedKeyboard — the SAME primitive as the chat
// docks (use-keyboard-dock-padding). Deliberate: under RN 0.81 enforced
// edge-to-edge, BOTH KeyboardAvoidingView and react-native-keyboard-controller
// proved unreliable (saga 2026-06-10); reading the exact IME height off the OS
// window is the only approach that held.
//
// Two mechanisms:
//   1. A bottom spacer animated to the keyboard height → the content has room
//      to scroll every field (even the last) above the IME.
//   2. When the keyboard settles, the currently-focused input is measured
//      against the scroll viewport and scrolled up if it sits behind the IME —
//      the window doesn't resize here (we own the inset), so RN's built-in
//      scroll-to-focused never fires; this replaces it.

interface Props extends ScrollViewProps {
  children: ReactNode;
  // Resting bottom padding (nav-bar inset etc.) that applies even keyboard-down.
  restBottom?: number;
}

export const KeyboardAwareScrollView = forwardRef<ComponentRef<typeof Animated.ScrollView>, Props>(
  function KeyboardAwareScrollView({ children, restBottom = 0, onScroll, ...rest }, ref) {
    const innerRef = useRef<ScrollView | null>(null);
    const offsetY = useRef(0);

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

    // Bring the focused input above the keyboard top. measureInWindow gives
    // absolute screen coords (works under Fabric, unlike measureLayout with a
    // numeric handle); compare its bottom to the keyboard top and scroll by the
    // overlap. Runs on the JS thread — reanimated triggers it after the IME
    // height settles.
    const scrollFocusedIntoView = useCallback((kbHeight: number) => {
      const scroll = innerRef.current;
      const focused = TextInput.State.currentlyFocusedInput?.();
      if (!scroll || !focused || kbHeight <= 0) return;
      const run = () => {
        focused.measureInWindow?.((_x: number, y: number, _w: number, h: number) => {
          const keyboardTop = Dimensions.get('window').height - kbHeight;
          const margin = spacing.lg;
          const overlap = (y + h) - (keyboardTop - margin);
          if (overlap > 0) {
            scroll.scrollTo({ y: offsetY.current + overlap, animated: true });
          }
        });
      };
      // Defer a frame so the measure reflects the settled keyboard layout.
      requestAnimationFrame(run);
    }, []);

    useAnimatedReaction(
      () => keyboard.height.value,
      (h, prev) => {
        if (h > 0 && h !== prev) runOnJS(scrollFocusedIntoView)(h);
      },
    );

    const handleScroll = useCallback(
      (e: NativeSyntheticEvent<NativeScrollEvent>) => {
        offsetY.current = e.nativeEvent.contentOffset.y;
        onScroll?.(e);
      },
      [onScroll],
    );

    return (
      <Animated.ScrollView
        ref={(node) => {
          innerRef.current = node as unknown as ScrollView | null;
          if (typeof ref === 'function') ref(node);
          else if (ref) ref.current = node;
        }}
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode="interactive"
        scrollEventThrottle={16}
        onScroll={handleScroll}
        {...rest}
      >
        {children}
        <Animated.View style={spacerStyle} />
      </Animated.ScrollView>
    );
  },
);
