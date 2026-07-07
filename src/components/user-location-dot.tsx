import { useEffect } from 'react';
import { StyleSheet, View } from 'react-native';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withRepeat,
  withTiming,
  Easing,
  useReducedMotion,
  cancelAnimation,
} from 'react-native-reanimated';

const GPS_BLUE = '#4285F4';

// The user's position marker on the map: a solid blue dot (white-bordered) with
// a translucent halo, plus two phase-shifted rings that expand outward and fade
// — Google-Maps' "you are here, live" pulse. The rings scale via transform, so
// they overflow the 22px container WITHOUT resizing it — keeping the parent
// MarkerView's anchoring stable. Honors the OS reduce-motion setting (rings off,
// static dot remains).
export function UserLocationDot() {
  const reduced = useReducedMotion();
  const progress = useSharedValue(0);

  useEffect(() => {
    if (reduced) return;
    progress.value = withRepeat(
      withTiming(1, { duration: 2200, easing: Easing.out(Easing.ease) }),
      -1,
      false,
    );
    return () => cancelAnimation(progress);
  }, [reduced, progress]);

  const ring1 = useAnimatedStyle(() => ({
    transform: [{ scale: 0.6 + progress.value * 2.6 }],
    opacity: 0.5 * (1 - progress.value),
  }));
  const ring2 = useAnimatedStyle(() => {
    const t = (progress.value + 0.5) % 1;
    return {
      transform: [{ scale: 0.6 + t * 2.6 }],
      opacity: 0.5 * (1 - t),
    };
  });

  return (
    <View style={styles.container}>
      {!reduced && <Animated.View style={[styles.ring, ring1]} />}
      {!reduced && <Animated.View style={[styles.ring, ring2]} />}
      <View style={styles.halo} />
      <View style={styles.core} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    width: 22,
    height: 22,
    alignItems: 'center',
    justifyContent: 'center',
  },
  ring: {
    position: 'absolute',
    width: 22,
    height: 22,
    borderRadius: 11,
    backgroundColor: 'rgba(66, 133, 244, 0.35)',
  },
  halo: {
    position: 'absolute',
    width: 22,
    height: 22,
    borderRadius: 11,
    backgroundColor: 'rgba(66, 133, 244, 0.25)',
  },
  core: {
    width: 14,
    height: 14,
    borderRadius: 7,
    backgroundColor: GPS_BLUE,
    borderWidth: 2.5,
    borderColor: '#FFFFFF',
  },
});
