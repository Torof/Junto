import { useEffect, useMemo } from 'react';
import { Pressable, View, StyleSheet } from 'react-native';
import Animated, { useSharedValue, useAnimatedStyle, withTiming } from 'react-native-reanimated';
import { Navigation2 } from 'lucide-react-native';
import { useTranslation } from 'react-i18next';
import { spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

interface Props {
  heading: number; // map bearing in degrees
  onPress: () => void; // reset to north
}

// Custom compass — styled to match the recenter / create buttons. The needle
// points at true north; tapping snaps the map back to north. Like a standard map
// compass, it only appears while the map is rotated and fades out at north.
export function CompassButton({ heading, onPress }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const norm = ((heading % 360) + 360) % 360; // 0..360
  const rotated = norm > 0.5 && norm < 359.5;

  const opacity = useSharedValue(0);
  useEffect(() => {
    opacity.value = withTiming(rotated ? 1 : 0, { duration: 180 });
  }, [rotated, opacity]);
  const fade = useAnimatedStyle(() => ({ opacity: opacity.value }));

  return (
    <Animated.View style={[styles.button, fade]} pointerEvents={rotated ? 'auto' : 'none'}>
      <Pressable style={styles.press} onPress={onPress} hitSlop={8} accessibilityLabel={t('map.north', { defaultValue: 'Nord' })}>
        <View style={{ transform: [{ rotate: `${-heading}deg` }] }}>
          <Navigation2 size={20} color={colors.cta} fill={colors.cta} strokeWidth={1.5} />
        </View>
      </Pressable>
    </Animated.View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  // Bottom-right, just above the recenter button — same round chip as the
  // recenter / create pair so the three read as one uniform stack.
  button: {
    position: 'absolute',
    bottom: 28 + 48 + 14 + 48 + 14,
    right: spacing.md,
    backgroundColor: colors.surface,
    borderRadius: radius.full,
    width: 48,
    height: 48,
    zIndex: 10,
    borderWidth: 1,
    borderColor: colors.border,
    elevation: 4,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.15,
    shadowRadius: 4,
  },
  press: { width: '100%', height: '100%', alignItems: 'center', justifyContent: 'center' },
});
