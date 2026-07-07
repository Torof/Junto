import { useMemo, useState } from 'react';
import { Keyboard, Pressable, StyleSheet, Text, View } from 'react-native';
import Animated, { runOnJS, useAnimatedKeyboard, useAnimatedReaction, useAnimatedStyle } from 'react-native-reanimated';
import { useTranslation } from 'react-i18next';
import { Check } from 'lucide-react-native';
import { fontSizes, spacing } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

// A "Terminé" accessory bar pinned just above the keyboard — the dismiss
// affordance multiline fields lack (their return key inserts a newline, so
// there's no Done). Follows the IME via reanimated's useAnimatedKeyboard (the
// primitive that works under edge-to-edge). Mounted only while the keyboard is
// up. Drop it once per screen that has text inputs.

export function KeyboardDoneBar() {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const [visible, setVisible] = useState(false);

  const keyboard = useAnimatedKeyboard({
    isStatusBarTranslucentAndroid: true,
    isNavigationBarTranslucentAndroid: true,
  });

  useAnimatedReaction(
    () => keyboard.height.value > 0,
    (up, prev) => {
      if (up !== prev) runOnJS(setVisible)(up);
    },
  );

  // Sit flush on top of the keyboard, tracking it as it animates.
  const barStyle = useAnimatedStyle(() => ({ bottom: keyboard.height.value }));

  if (!visible) return null;

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
