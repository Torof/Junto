import { memo } from 'react';
import { StyleSheet } from 'react-native';
import Svg, { Path } from 'react-native-svg';

// Topographic contour lines — the Partenaires surfaces' texture (the map's
// own vocabulary, no photo of anyone). Drawn over a solid fill, absolutely
// positioned; `opacity` of the white lines sets the strength.
export const ContourLines = memo(function ContourLines({ width, height, opacity = 0.18 }: {
  width: number;
  height: number;
  opacity?: number;
}) {
  const rows = Math.max(3, Math.round(height / 26));
  const paths = Array.from({ length: rows }, (_, i) => {
    const y = 18 + i * (height / rows);
    const a = width * 0.28;
    const b = width * 0.62;
    return `M -10 ${y} C ${a} ${y - 22} ${a + 30} ${y + 30} ${b} ${y} S ${width - 20} ${y - 18} ${width + 10} ${y + 6}`;
  });
  return (
    <Svg width={width} height={height} style={StyleSheet.absoluteFill} pointerEvents="none">
      {paths.map((d, i) => (
        <Path key={i} d={d} stroke="#FFFFFF" strokeOpacity={opacity} strokeWidth={1.3} fill="none" />
      ))}
    </Svg>
  );
});
