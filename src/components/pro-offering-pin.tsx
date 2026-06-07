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
// Shrunk from 56 to 40 to match the activity pin's lighter footprint.
const PIN_WIDTH = 40;
const PIN_HEIGHT = Math.round((PIN_WIDTH * VIEWBOX_H) / VIEWBOX_W);
// Geometric center of the new octagon body (y range 14..60).
const ICON_CENTER_Y_VBX = 37;

// Regular stop-sign octagon — 46x46 (all 8 sides ≈19 viewBox units).
// Positioned at x=4..50, y=14..60 so the bottom edge anchor stays at
// (27, 60), matching the previous pin's geographic registration.
// Rounded corners (r≈3) keep the silhouette smooth without breaking
// regularity.
const PIN_PATH =
  'M 20.5 14 L 33.5 14 Q 36.5 14 38.6 16.1 L 47.9 25.4 Q 50 27.5 50 30.5 L 50 43.5 Q 50 46.5 47.9 48.6 L 38.6 57.9 Q 36.5 60 33.5 60 L 20.5 60 Q 17.5 60 15.4 57.9 L 6.1 48.6 Q 4 46.5 4 43.5 L 4 30.5 Q 4 27.5 6.1 25.4 L 15.4 16.1 Q 17.5 14 20.5 14 Z';

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
    fontSize: 12,
  },
});
