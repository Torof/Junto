import { memo, useMemo } from 'react';
import { View, StyleSheet } from 'react-native';
import { AppText } from '@/components/app-text';
import Svg, { Circle } from 'react-native-svg';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { useClusterStyleStore } from '@/store/cluster-style-store';

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
const GAP = 1.5;         // white gap between two slices (px of arc)
const MIN_SHARE = 0.08;  // smallest slice drawn, so a 1-in-20 stays visible

function clusterSize(count: number): number {
  if (count < 2) return MIN_SIZE;
  // Whole pixels: a fractional box gets floored by layout while the svg draws
  // at full size, which clipped the outline on the bottom/right edges.
  return Math.round(Math.max(MIN_SIZE, Math.min(MAX_SIZE, 36 + Math.log10(count) * 12)));
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
  const ringOn = useClusterStyleStore((s) => s.ringOn);
  const RING = useClusterStyleStore((s) => s.ringWidth);

  const c = size / 2;
  const outline = c - 1;              // ink outline centre line, 0.5px clear of the edge
  const r = outline - 0.5 - RING / 2; // ring sits flush inside the outline
  const circ = 2 * Math.PI * r;
  // Ring off → the plain white bubble with an ink outline (pre-2026-10-21 look).
  const parts = ringOn ? segments.filter((s) => s.count > 0) : [];
  const fr = shares(parts);
  const gap = parts.length > 1 ? GAP : 0;
  let offset = 0;

  return (
    <View style={[styles.cluster, { width: size, height: size }]}>
      {/* Outline + ring share ONE svg (same centre). A View border would push
          the absolutely-filled svg 1px down-right (it fills the padding box). */}
      <Svg width={size} height={size} style={styles.svg}>
        {parts.length === 0 ? (
          // Ring off: ONE 2px ink border on the white disc — the pre-2026-10-21
          // look (an extra inner circle used to draw a second black ring).
          <Circle cx={c} cy={c} r={c - 1} fill={colors.background} stroke={colors.pinBorder} strokeWidth={2} />
        ) : (
          <Circle cx={c} cy={c} r={outline} fill={colors.background} stroke={colors.pinBorder} strokeWidth={1} />
        )}
        {parts.length > 0 &&
          parts.map((p, i) => {
            const len = Math.max(fr[i]! * circ - gap, 0.5);
            const el = (
              <Circle
                key={p.color + i}
                cx={c}
                cy={c}
                r={r}
                stroke={p.color}
                strokeWidth={RING}
                fill="none"
                strokeDasharray={`${len} ${circ - len}`}
                strokeDashoffset={-offset}
                transform={`rotate(-90 ${c} ${c})`}
              />
            );
            offset += fr[i]! * circ;
            return el;
          })}
      </Svg>
      <AppText style={[styles.count, { fontSize }]}>{label}</AppText>
    </View>
  );
});

const createStyles = (colors: AppColors) => StyleSheet.create({
  // Transparent box: the white disc + outline + ring are all drawn in the svg.
  cluster: {
    alignItems: 'center',
    justifyContent: 'center',
  },
  svg: {
    position: 'absolute',
    left: 0,
    top: 0,
  },
  count: {
    color: colors.textPrimary,
    fontWeight: 'bold',
  },
});
