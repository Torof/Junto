import { View, StyleSheet } from 'react-native';

interface MapPinProps {
  color: string;
  size?: number;
}

export function MapPinIcon({ color, size = 30 }: MapPinProps) {
  const dotSize = size * 0.4;

  return (
    <View style={[styles.container, { width: size, height: size * 1.4 }]}>
      {/* Pin head */}
      <View style={[styles.head, { width: size, height: size, borderRadius: size / 2, backgroundColor: color }]}>
        <View style={[styles.dot, { width: dotSize, height: dotSize, borderRadius: dotSize / 2 }]} />
      </View>
      {/* Pin tail */}
      <View
        style={[
          styles.tail,
          {
            borderLeftWidth: size * 0.3,
            borderRightWidth: size * 0.3,
            borderTopWidth: size * 0.5,
            borderTopColor: color,
            marginTop: -(size * 0.1),
          },
        ]}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    alignItems: 'center',
  },
  head: {
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 1,
  },
  dot: {
    backgroundColor: 'white',
  },
  tail: {
    width: 0,
    height: 0,
    borderLeftColor: 'transparent',
    borderRightColor: 'transparent',
  },
});
