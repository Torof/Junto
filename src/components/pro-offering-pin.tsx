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

// Hexagon pin — visually distinct from the activity teardrop and the
// pro storefront square. Reads as "fixed POI / faceted offering"
// rather than "event happening now". Sport-category color so the eye
// still scans by sport across all three pin types.

const VIEWBOX_W = 54;
const VIEWBOX_H = 64;
const PIN_WIDTH = 56;
const PIN_HEIGHT = Math.round((PIN_WIDTH * VIEWBOX_H) / VIEWBOX_W);
const ICON_CENTER_Y_VBX = 32;

// Pointy-top hexagon, anchored on the bottom vertex (27, 60).
// Vertices, clockwise from top:
//   top (27, 4) → top-right (50, 18) → bottom-right (50, 46)
//   → bottom (27, 60) → bottom-left (4, 46) → top-left (4, 18) → close
const PIN_PATH = 'M 27 4 L 50 18 L 50 46 L 27 60 L 4 46 L 4 18 Z';

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
