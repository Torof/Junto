import { useEffect, useRef } from 'react';
import { Animated, type DimensionValue, type StyleProp, type ViewStyle } from 'react-native';
import { useColors } from '@/hooks/use-theme';

// A grey placeholder block that pulses while its content loads.
export function Bone({ width, height, style }: { width: DimensionValue; height?: number; style?: StyleProp<ViewStyle> }) {
  const colors = useColors();
  const opacity = useRef(new Animated.Value(0.3)).current;

  useEffect(() => {
    const anim = Animated.loop(
      Animated.sequence([
        Animated.timing(opacity, { toValue: 0.6, duration: 800, useNativeDriver: true }),
        Animated.timing(opacity, { toValue: 0.3, duration: 800, useNativeDriver: true }),
      ]),
    );
    anim.start();
    return () => anim.stop();
  }, [opacity]);

  return <Animated.View style={[{ width, height, borderRadius: 4, backgroundColor: colors.surfaceAlt, opacity }, style]} />;
}
