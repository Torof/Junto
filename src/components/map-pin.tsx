import { View, StyleSheet } from 'react-native';
import Svg, { Circle, Path } from 'react-native-svg';

interface MapPinProps {
  color: string;
}

const WIDTH = 16;
const HEIGHT = 22;
const HEAD_RADIUS = 7;
const HEAD_CY = 7;
const TAIL_COLOR = '#5A5A5A';

export function MapPinIcon({ color }: MapPinProps) {
  return (
    <View style={styles.container}>
      <Svg width={WIDTH} height={HEIGHT} viewBox={`0 0 ${WIDTH} ${HEIGHT}`}>
        {/* Tail: thin triangle from head bottom down to tip */}
        <Path
          d={`M ${WIDTH / 2 - 2.5} ${HEAD_CY + HEAD_RADIUS - 2} L ${WIDTH / 2 + 2.5} ${HEAD_CY + HEAD_RADIUS - 2} L ${WIDTH / 2} ${HEIGHT} Z`}
          fill={TAIL_COLOR}
        />
        {/* Head */}
        <Circle cx={WIDTH / 2} cy={HEAD_CY} r={HEAD_RADIUS} fill={color} />
        {/* Inner highlight */}
        <Circle cx={WIDTH / 2} cy={HEAD_CY} r={2.2} fill="rgba(255,255,255,0.85)" />
      </Svg>
    </View>
  );
}

// Anchor so the tip of the tail sits on the geographic point.
export const MAP_PIN_ANCHOR = { x: 0.5, y: 1 } as const;

const styles = StyleSheet.create({
  container: {
    width: WIDTH,
    height: HEIGHT,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.3,
    shadowRadius: 1.5,
    elevation: 2,
  },
});
