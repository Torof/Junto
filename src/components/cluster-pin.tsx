import { memo, useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import Svg, { Circle } from 'react-native-svg';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';

export interface ClusterSegment {
  color: string;
  count: number;
}

interface ClusterPinProps {
  count: number;
  /** Share of the cluster per universe, drawn as a ring around the count. */
  segments?: ClusterSegment[];
}

const MIN_SIZE = 36;
const MAX_SIZE = 60;
const RING = 5;          // ring thickness (px)
const GAP = 1.5;         // white gap between two slices (px of arc)
const MIN_SHARE = 0.08;  // smallest slice drawn, so a 1-in-20 stays visible

function clusterSize(count: number): number {
  if (count < 2) return MIN_SIZE;
  return Math.max(MIN_SIZE, Math.min(MAX_SIZE, 36 + Math.log10(count) * 12));
}

function formatClusterCount(n: number): string {
  if (n < 1000) return String(n);
  if (n < 10000) {
    const v = (n / 1000).toFixed(1);
    return `${v.endsWith('.0') ? v.slice(0, -2) : v}k`;
  }
  return `${Math.floor(n / 1000)}k`;
}

// Fractions with a floor, renormalised so the ring always closes.
function shares(segments: ClusterSegment[]): number[] {
  const total = segments.reduce((s, x) => s + x.count, 0) || 1;
  const floored = segments.map((x) => Math.max(x.count / total, MIN_SHARE));
  const sum = floored.reduce((s, f) => s + f, 0);
  return floored.map((f) => f / sum);
}

// Cluster bubble: count in the centre, a donut ring split by universe colour
// (Scott 2026-10-21 — « un camembert », ring chosen so the number stays legible).
export const ClusterPin = memo(function ClusterPin({ count, segments = [] }: ClusterPinProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const size = clusterSize(count);
  const label = formatClusterCount(count);
  const fontSize = size <= 44 ? 13 : size <= 52 ? 15 : 17;

  const r = (size - RING) / 2 - 1; // 1px inside the outer ink outline
  const circ = 2 * Math.PI * r;
  const parts = segments.filter((s) => s.count > 0);
  const fr = shares(parts);
  const gap = parts.length > 1 ? GAP : 0;
  let offset = 0;

  return (
    <View style={[styles.cluster, { width: size, height: size, borderRadius: size / 2 }]}>
      <Svg width={size} height={size} style={StyleSheet.absoluteFill}>
        {parts.length === 0 ? (
          <Circle cx={size / 2} cy={size / 2} r={r} stroke={colors.pinBorder} strokeWidth={2} fill="none" />
        ) : (
          parts.map((p, i) => {
            const len = Math.max(fr[i]! * circ - gap, 0.5);
            const el = (
              <Circle
                key={p.color + i}
                cx={size / 2}
                cy={size / 2}
                r={r}
                stroke={p.color}
                strokeWidth={RING}
                fill="none"
                strokeDasharray={`${len} ${circ - len}`}
                strokeDashoffset={-offset}
                transform={`rotate(-90 ${size / 2} ${size / 2})`}
              />
            );
            offset += fr[i]! * circ;
            return el;
          })
        )}
      </Svg>
      <Text style={[styles.count, { fontSize }]}>{label}</Text>
    </View>
  );
});

const createStyles = (colors: AppColors) => StyleSheet.create({
  cluster: {
    backgroundColor: colors.background,
    borderWidth: 1,
    borderColor: colors.pinBorder,
    alignItems: 'center',
    justifyContent: 'center',
  },
  count: {
    color: colors.textPrimary,
    fontWeight: 'bold',
  },
});
