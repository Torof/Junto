import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import Svg, { Path } from 'react-native-svg';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

export type PageType = 'pro' | 'offering' | 'activity';

interface Props {
  type: PageType;
}

// Small pin-silhouette + short label rendered into the navbar of the
// pro / offering / activity detail screens. Mirrors the map's pin
// vocabulary (square = pro storefront, octagon = catalog offering,
// teardrop = scheduled activity) so the user can see at a glance
// what kind of page they're on.

// Simplified silhouettes — sport icon and per-instance details are
// stripped. We only need the shape's profile at this small scale.
const TEARDROP_PATH = 'M 27 2 C 13 2 4 12 4 25 C 4 38 27 62 27 62 C 27 62 50 38 50 25 C 50 12 41 2 27 2 Z';
const SQUARE_PATH =
  'M 6 2 L 44 2 Q 48 2 48 6 L 48 42 Q 48 46 44 46 L 6 46 Q 2 46 2 42 L 2 6 Q 2 2 6 2 Z';
const OCTAGON_PATH =
  'M 20.5 14 L 33.5 14 Q 36.5 14 38.6 16.1 L 47.9 25.4 Q 50 27.5 50 30.5 L 50 43.5 Q 50 46.5 47.9 48.6 L 38.6 57.9 Q 36.5 60 33.5 60 L 20.5 60 Q 17.5 60 15.4 57.9 L 6.1 48.6 Q 4 46.5 4 43.5 L 4 30.5 Q 4 27.5 6.1 25.4 L 15.4 16.1 Q 17.5 14 20.5 14 Z';

const SVG_SIZE = 18;

export function PageTypeBadge({ type }: Props) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const { path, viewBoxW, viewBoxH, label } = (() => {
    switch (type) {
      case 'pro':
        return { path: SQUARE_PATH, viewBoxW: 50, viewBoxH: 46, label: 'PRO' };
      case 'offering':
        return { path: OCTAGON_PATH, viewBoxW: 54, viewBoxH: 64, label: 'OFFRE' };
      case 'activity':
        return { path: TEARDROP_PATH, viewBoxW: 54, viewBoxH: 64, label: 'SORTIE' };
    }
  })();

  return (
    <View style={styles.wrap}>
      <Svg width={SVG_SIZE} height={SVG_SIZE} viewBox={`0 0 ${viewBoxW} ${viewBoxH}`}>
        <Path
          d={path}
          fill={colors.cta}
          stroke={colors.pinBorder}
          strokeWidth={2}
          strokeOpacity={0.55}
          strokeLinejoin="round"
        />
      </Svg>
      <Text style={styles.label}>{label}</Text>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  wrap: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    paddingHorizontal: spacing.xs + 2,
    paddingVertical: 3,
    borderRadius: radius.sm,
    borderWidth: 1,
    borderColor: colors.borderMuted,
  },
  label: {
    color: colors.textPrimary,
    fontSize: fontSizes.xs - 1,
    fontWeight: '800',
    letterSpacing: 1,
  },
});
