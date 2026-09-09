import { useEffect, useMemo, useState } from 'react';
import { Keyboard, Platform, Pressable, StyleSheet, Text, View } from 'react-native';
import Animated, { useAnimatedKeyboard, useAnimatedStyle } from 'react-native-reanimated';
import { useIsFocused } from '@react-navigation/native';
import { useTranslation } from 'react-i18next';
import { Check } from 'lucide-react-native';
import { fontSizes, spacing } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

// A "Terminé" accessory bar pinned just above the keyboard — the dismiss
// affordance multiline fields lack (their return key inserts a newline, so
// there's no Done). Follows the IME via reanimated's useAnimatedKeyboard (the
// primitive that works under edge-to-edge). Drop it once per screen that has
// text inputs.
//
// Visibility is driven by the real Keyboard show/hide events, NOT by
// `keyboard.height.value > 0`: on Android edge-to-edge that height can rest at a
// stale non-zero value, which left the bar stuck mid-screen. We also hide when
// the screen isn't focused — Expo Router keeps previous stack screens mounted,
// so a background step's bar could otherwise show through.

export function KeyboardDoneBar() {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const [kbdUp, setKbdUp] = useState(false);
  const focused = useIsFocused();

  const keyboard = useAnimatedKeyboard({
    isStatusBarTranslucentAndroid: true,
    isNavigationBarTranslucentAndroid: true,
  });

  useEffect(() => {
    const showEvt = Platform.OS === 'ios' ? 'keyboardWillShow' : 'keyboardDidShow';
    const hideEvt = Platform.OS === 'ios' ? 'keyboardWillHide' : 'keyboardDidHide';
    const show = Keyboard.addListener(showEvt, () => setKbdUp(true));
    const hide = Keyboard.addListener(hideEvt, () => setKbdUp(false));
    return () => { show.remove(); hide.remove(); };
  }, []);

  // Sit flush on top of the keyboard, tracking it as it animates.
  const barStyle = useAnimatedStyle(() => ({ bottom: keyboard.height.value }));

  if (!kbdUp || !focused) return null;

  return (
    <Animated.View style={[styles.bar, barStyle]}>
      <View style={styles.spacer} />
      <Pressable onPress={() => Keyboard.dismiss()} hitSlop={8} style={styles.btn}>
        <Text style={styles.btnText}>{t('common.done', { defaultValue: 'Terminé' })}</Text>
        <Check size={16} color={colors.cta} strokeWidth={2.6} />
      </Pressable>
    </Animated.View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  bar: {
    position: 'absolute',
    left: 0,
    right: 0,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surfaceAlt,
    borderTopWidth: 1,
    borderTopColor: colors.borderMuted,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.xs + 2,
  },
  spacer: { flex: 1 },
  btn: { flexDirection: 'row', alignItems: 'center', gap: 5, paddingVertical: 4, paddingHorizontal: 4 },
  btnText: { color: colors.cta, fontSize: fontSizes.md, fontWeight: '800' },
});
