import { useMemo } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withSequence,
  withTiming,
  withSpring,
  Easing,
  useReducedMotion,
} from 'react-native-reanimated';
import { useTranslation } from 'react-i18next';
import { spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

const GPS_BLUE = '#4285F4';

interface RecenterButtonProps {
  onPress: () => void;
}

export function RecenterButton({ onPress }: RecenterButtonProps) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const reduced = useReducedMotion();

  const scale = useSharedValue(1);
  const dotStyle = useAnimatedStyle(() => ({ transform: [{ scale: scale.value }] }));

  const handlePress = () => {
    // Grow-and-return tap feedback — the GPS dot swells then springs back,
    // echoing the pulse on the map's location marker.
    if (!reduced) {
      scale.value = withSequence(
        withTiming(1.35, { duration: 160, easing: Easing.out(Easing.quad) }),
        withSpring(1, { damping: 7, stiffness: 190 }),
      );
    }
    onPress();
  };

  return (
    <Pressable style={styles.button} onPress={handlePress} hitSlop={8} accessibilityLabel={t('map.recenter')}>
      {/* GPS-dot icon: translucent halo + solid blue dot (white-bordered),
          the same marker the map draws for 'my position'. */}
      <Animated.View style={[styles.dot, dotStyle]}>
        <View style={styles.dotHalo} />
        <View style={styles.dotCore} />
      </Animated.View>
    </Pressable>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  // Bottom-right, just above the create FAB. Same size as the FAB so they
  // read as a uniform round pair, only the fill changes.
  button: {
    position: 'absolute',
    bottom: 28 + 48 + 14,
    right: spacing.md,
    backgroundColor: colors.surface,
    borderRadius: radius.full,
    width: 48,
    height: 48,
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 10,
    borderWidth: 1,
    borderColor: colors.border,
    elevation: 4,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.15,
    shadowRadius: 4,
  },
  dot: {
    width: 22,
    height: 22,
    alignItems: 'center',
    justifyContent: 'center',
  },
  dotHalo: {
    position: 'absolute',
    width: 22,
    height: 22,
    borderRadius: 11,
    backgroundColor: 'rgba(66, 133, 244, 0.20)',
  },
  dotCore: {
    width: 12,
    height: 12,
    borderRadius: 6,
    backgroundColor: GPS_BLUE,
    borderWidth: 2,
    borderColor: '#FFFFFF',
  },
});
