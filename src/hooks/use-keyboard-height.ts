import { useEffect, useState } from 'react';
import { Keyboard, Platform } from 'react-native';

// Current soft-keyboard height (0 when hidden), from the OS keyboard
// events. Chat screens use it to place the input dock directly above
// the IME on Android: under RN 0.81 enforced edge-to-edge the window
// never resizes and KeyboardAvoidingView's frame math is unreliable
// (offset 100 left a large gap, offset 0 hid the dock), so the dock
// is driven by the reported height instead — no frame arithmetic.
export function useKeyboardHeight(): number {
  const [height, setHeight] = useState(0);

  useEffect(() => {
    const showEvent = Platform.OS === 'ios' ? 'keyboardWillShow' : 'keyboardDidShow';
    const hideEvent = Platform.OS === 'ios' ? 'keyboardWillHide' : 'keyboardDidHide';
    const show = Keyboard.addListener(showEvent, (e) => setHeight(e.endCoordinates.height));
    const hide = Keyboard.addListener(hideEvent, () => setHeight(0));
    return () => {
      show.remove();
      hide.remove();
    };
  }, []);

  return height;
}
