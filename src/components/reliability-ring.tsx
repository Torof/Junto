import { View, StyleSheet } from 'react-native';
import Svg, { Circle } from 'react-native-svg';
import { colors } from '@/constants/theme';

interface Props {
  score: number | null;
  size: number;
  strokeWidth?: number;
  children: React.ReactNode;
}

function colorFor(score: number): string {
  if (score >= 90) return colors.success;
  if (score >= 70) return colors.warning;
  return colors.error;
}

export function ReliabilityRing({ score, size, strokeWidth = 3, children }: Props) {
  const outerSize = size + strokeWidth * 2 + 4;
  const center = outerSize / 2;
  const svgRadius = (size + strokeWidth) / 2;
  const circumference = 2 * Math.PI * svgRadius;

  const clamped = score !== null ? Math.max(0, Math.min(100, score)) : 0;
  const progress = clamped / 100;
  const strokeDashoffset = circumference * (1 - progress);
  const ringColor = score !== null ? colorFor(clamped) : colors.surface;

  return (
    <View style={[styles.container, { width: outerSize, height: outerSize }]}>
      <Svg width={outerSize} height={outerSize} style={StyleSheet.absoluteFill}>
        <Circle
          cx={center}
          cy={center}
          r={svgRadius}
          stroke={colors.surface}
          strokeWidth={strokeWidth}
          fill="none"
        />
        {score !== null && (
          <Circle
            cx={center}
            cy={center}
            r={svgRadius}
            stroke={ringColor}
            strokeWidth={strokeWidth}
            fill="none"
            strokeDasharray={`${circumference}`}
            strokeDashoffset={strokeDashoffset}
            strokeLinecap="round"
            rotation={-90}
            origin={`${center}, ${center}`}
          />
        )}
      </Svg>
      <View style={styles.content}>
        {children}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    alignItems: 'center',
    justifyContent: 'center',
  },
  content: {
    position: 'absolute',
  },
});
