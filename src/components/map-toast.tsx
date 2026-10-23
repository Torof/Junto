import { useEffect, useMemo, useRef, useState } from 'react';
import { Animated, StyleSheet } from 'react-native';
import { AppText } from '@/components/app-text';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { useMapToastStore } from '@/store/map-toast-store';

// Bottom of the floating controls (recenter button: 28 + 48 + 14) — the pill
// sits on that line, centred, clear of the drawer handle and the side buttons.
const BOTTOM = 28 + 48 + 14;
const HOLD_MS = 1400;

export function MapToast() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const message = useMapToastStore((s) => s.message);
  const nonce = useMapToastStore((s) => s.nonce);
  const opacity = useRef(new Animated.Value(0)).current;
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    if (!message || nonce === 0) return;
    setVisible(true);
    opacity.stopAnimation();
    Animated.sequence([
      Animated.timing(opacity, { toValue: 1, duration: 140, useNativeDriver: true }),
      Animated.delay(HOLD_MS),
      Animated.timing(opacity, { toValue: 0, duration: 220, useNativeDriver: true }),
    ]).start(({ finished }) => { if (finished) setVisible(false); });
  }, [message, nonce, opacity]);

  if (!visible || !message) return null;
  return (
    <Animated.View style={[styles.pill, { opacity }]} pointerEvents="none">
      <AppText style={styles.text} numberOfLines={1}>{message}</AppText>
    </Animated.View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  pill: {
    position: 'absolute',
    bottom: BOTTOM + 6,
    alignSelf: 'center',
    maxWidth: '70%',
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    borderRadius: radius.full,
    backgroundColor: colors.textPrimary,
    elevation: 4,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.18,
    shadowRadius: 4,
  },
  text: {
    color: colors.surface,
    fontSize: fontSizes.sm,
    fontWeight: '700',
  },
});
