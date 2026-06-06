import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import Svg, { Path } from 'react-native-svg';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { getSportIcon } from '@/constants/sport-icons';
import { type ProOffering } from '@/services/pro-offering-service';

interface ProOfferingPinProps {
  offering: ProOffering;
}

// Octagon pin — visually distinct from the activity teardrop and the
// pro storefront square. Reads as "fixed POI / faceted offering".
// Stop-sign orientation with flat top + bottom edges (anchors on the
// center of the bottom edge, which gives a grounded feel vs the hex's
// diamond-like point anchor). Same sport-category color treatment as
// the rest of the pin family.

const VIEWBOX_W = 54;
const VIEWBOX_H = 64;
const PIN_WIDTH = 56;
const PIN_HEIGHT = Math.round((PIN_WIDTH * VIEWBOX_H) / VIEWBOX_W);
const ICON_CENTER_Y_VBX = 32;

// Stretched stop-sign octagon (width 46, height 56) with rounded
// corners (r≈3 in viewBox units) for consistency with the previous
// hex's curved-vertex treatment. Eight vertices, 13-unit corner cuts,
// each vertex softened with a quadratic Bezier so the silhouette
// reads smooth instead of jagged.
const PIN_PATH =
  'M 20 4 L 34 4 Q 37 4 39.1 6.1 L 47.9 14.9 Q 50 17 50 20 L 50 44 Q 50 47 47.9 49.1 L 39.1 57.9 Q 37 60 34 60 L 20 60 Q 17 60 14.9 57.9 L 6.1 49.1 Q 4 47 4 44 L 4 20 Q 4 17 6.1 14.9 L 14.9 6.1 Q 17 4 20 4 Z';

export const PRO_OFFERING_PIN_ANCHOR = { x: 0.5, y: 60 / VIEWBOX_H };

export function ProOfferingPin({ offering }: ProOfferingPinProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  return (
    <View style={styles.wrapper}>
      <Svg width={PIN_WIDTH} height={PIN_HEIGHT} viewBox={`0 0 ${VIEWBOX_W} ${VIEWBOX_H}`}>
        <Path
          d={PIN_PATH}
          fill={colors.pinBackground}
          stroke={colors.pinBorder}
          strokeWidth={2}
          strokeOpacity={0.55}
          strokeLinejoin="round"
        />
      </Svg>
      <View style={styles.iconWrap}>
        <Text style={styles.icon}>{getSportIcon(offering.sport_key)}</Text>
      </View>
    </View>
  );
}

const createStyles = (_colors: AppColors) => StyleSheet.create({
  wrapper: {
    width: PIN_WIDTH,
    height: PIN_HEIGHT,
    overflow: 'visible',
    shadowColor: '#0A0F1A',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.45,
    shadowRadius: 4,
    elevation: 6,
  },
  iconWrap: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: PIN_HEIGHT * (1 - 2 * (ICON_CENTER_Y_VBX / VIEWBOX_H)),
    alignItems: 'center',
    justifyContent: 'center',
  },
  icon: {
    fontSize: 16,
  },
});
