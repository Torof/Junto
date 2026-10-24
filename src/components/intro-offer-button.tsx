import { useEffect, useMemo } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';
import Animated, {
  Easing,
  useAnimatedStyle,
  useReducedMotion,
  useSharedValue,
  withDelay,
  withRepeat,
  withSequence,
  withTiming,
} from 'react-native-reanimated';
import { useTranslation } from 'react-i18next';
import { Sparkles, X } from 'lucide-react-native';
import { AppText } from '@/components/app-text';
import { fontSizes, radius, glow } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

// « Découvrir askandgo · 1 min » on the map (Scott 2026-10-24, option « C »):
// every 3 s the pill hops and flashes, then rests — it asks to be touched,
// opened or closed. Gone once the tour was opened or closed, or after a week
// (carte.tsx). Still for people who turned motion down on their phone.
export function IntroOfferButton({ onOpen, onClose }: { onOpen: () => void; onClose: () => void }) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const reduced = useReducedMotion();
  const lift = useSharedValue(0);
  const shine = useSharedValue(0);

  useEffect(() => {
    if (reduced) return;
    const ease = Easing.out(Easing.quad);
    lift.value = withRepeat(withSequence(
      withDelay(2100, withTiming(-8, { duration: 160, easing: ease })),
      withTiming(0, { duration: 170, easing: Easing.in(Easing.quad) }),
      withTiming(-3, { duration: 130, easing: ease }),
      withTiming(0, { duration: 140, easing: Easing.in(Easing.quad) }),
      withTiming(0, { duration: 300 }),
    ), -1);
    shine.value = withRepeat(withSequence(
      withDelay(2100, withTiming(1, { duration: 180 })),
      withTiming(0, { duration: 520 }),
      withTiming(0, { duration: 300 }),
    ), -1);
  }, [reduced, lift, shine]);

  const pillStyle = useAnimatedStyle(() => ({
    transform: [{ translateY: lift.value }, { scale: 1 + (-lift.value / 8) * 0.06 }],
  }));
  const shineStyle = useAnimatedStyle(() => ({ opacity: shine.value * 0.32 }));

  return (
    <Animated.View style={[styles.pill, glow(colors.cta), pillStyle]}>
      <Pressable onPress={onOpen} style={styles.main} accessibilityRole="button" hitSlop={6}>
        <Sparkles size={16} color={colors.onCta} strokeWidth={2.4} />
        <AppText style={styles.label}>{t('intro.offer')}</AppText>
      </Pressable>
      <Pressable onPress={onClose} style={styles.close} accessibilityRole="button" accessibilityLabel={t('intro.offerClose')} hitSlop={10}>
        <X size={12} color={colors.onCta} strokeWidth={3} />
      </Pressable>
      <Animated.View pointerEvents="none" style={[styles.shine, shineStyle]} />
    </Animated.View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  pill: {
    flexDirection: 'row',
    alignItems: 'center',
    alignSelf: 'center',
    backgroundColor: colors.cta,
    borderRadius: radius.full,
    paddingLeft: 14,
    paddingRight: 8,
    paddingVertical: 8,
    gap: 8,
  },
  main: { flexDirection: 'row', alignItems: 'center', gap: 7 },
  label: { color: colors.onCta, fontSize: fontSizes.sm, fontWeight: '800' },
  close: {
    width: 22,
    height: 22,
    borderRadius: 11,
    backgroundColor: 'rgba(255,255,255,0.25)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  shine: { ...StyleSheet.absoluteFillObject, borderRadius: radius.full, backgroundColor: '#FFFFFF' },
});

// The menu entry's icon square with a soft halo breathing out of it (option
// « A »): calmer than the map pill — the menu was opened on purpose.
export function HaloSquare({ children, size = 38 }: { children: React.ReactNode; size?: number }) {
  const colors = useColors();
  const reduced = useReducedMotion();
  const p = useSharedValue(0);
  useEffect(() => {
    if (reduced) return;
    p.value = withRepeat(withTiming(1, { duration: 1600, easing: Easing.out(Easing.quad) }), -1);
  }, [reduced, p]);
  const ring = useAnimatedStyle(() => ({ opacity: 0.6 * (1 - p.value), transform: [{ scale: 1 + p.value * 0.55 }] }));
  return (
    <View style={{ width: size, height: size, alignItems: 'center', justifyContent: 'center' }}>
      <Animated.View pointerEvents="none" style={[{ position: 'absolute', width: size, height: size, borderRadius: 12, backgroundColor: colors.cta }, ring]} />
      <View style={{ width: size, height: size, borderRadius: 12, backgroundColor: colors.cta, alignItems: 'center', justifyContent: 'center' }}>{children}</View>
    </View>
  );
}
