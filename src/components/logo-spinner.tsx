import { useEffect, useRef } from 'react';
import { Animated, Easing, Image, StyleSheet } from 'react-native';

const logo = require('../../assets/askandgo_icon_square.png');

// The askandgo mark turns like a coin spun on a table — a rotation around the
// vertical axis (Scott 2026-10-23, option « B » of the loader board).

interface Props {
  size?: number;
}

export function LogoSpinner({ size = 48 }: Props) {
  const rotation = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    const anim = Animated.loop(
      Animated.timing(rotation, {
        toValue: 1,
        duration: 1600,
        easing: Easing.linear,
        useNativeDriver: true,
      }),
    );
    anim.start();
    return () => anim.stop();
  }, [rotation]);

  const spin = rotation.interpolate({
    inputRange: [0, 1],
    outputRange: ['0deg', '360deg'],
  });

  return (
    <Animated.View style={[styles.container, { width: size, height: size, transform: [{ perspective: 400 }, { rotateY: spin }] }]}>
      <Image source={logo} style={{ width: size, height: size, borderRadius: size / 2 }} />
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  container: {
    alignItems: 'center',
    justifyContent: 'center',
  },
});
