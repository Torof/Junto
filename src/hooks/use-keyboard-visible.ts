import { useEffect, useState } from 'react';
import { Keyboard, Platform } from 'react-native';

// Whether the soft keyboard is currently up. Chat screens use this to
// drop the safe-area bottom padding while typing — the KAV already ends
// the layout at the keyboard top, so keeping the nav-bar inset there
// just reads as a dead gap between the input dock and the IME.
export function useKeyboardVisible(): boolean {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const showEvent = Platform.OS === 'ios' ? 'keyboardWillShow' : 'keyboardDidShow';
    const hideEvent = Platform.OS === 'ios' ? 'keyboardWillHide' : 'keyboardDidHide';
    const show = Keyboard.addListener(showEvent, () => setVisible(true));
    const hide = Keyboard.addListener(hideEvent, () => setVisible(false));
    return () => {
      show.remove();
      hide.remove();
    };
  }, []);

  return visible;
}
