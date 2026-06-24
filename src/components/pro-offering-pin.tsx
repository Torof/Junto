import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import Svg, { Path, Circle } from 'react-native-svg';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { getSportIcon } from '@/constants/sport-icons';
import { type ProOffering } from '@/services/pro-offering-service';

interface ProOfferingPinProps {
  offering: ProOffering;
}

// Pin system v3 (2026-06-11, Scott's call): RA pins use the EXACT same
// teardrop geometry as activity pins — they ARE activities ("recurring
// activities"), same "something to do here" promise. The frame color
// is the single semantic channel across all teardrops: beige published,
// green in-progress, amber soon… and ALWAYS pro-badge blue for RAs
// (they're unchanging, no temporal states). Circle pins stay reserved
// for the pros themselves (PP).
//
// Geometry mirrors activity-pin.tsx exactly (path, viewbox, plate,
// icon center, anchor) so the two render pixel-identically apart from
// the frame hue.

const VIEWBOX_W = 54;
const VIEWBOX_H = 64;
const PIN_WIDTH = 44;
const PIN_HEIGHT = Math.round((PIN_WIDTH * VIEWBOX_H) / VIEWBOX_W);
const ICON_CENTER_Y_VBX = 24;

const PIN_PATH = 'M 27 2 C 13 2 4 12 4 25 C 4 38 27 62 27 62 C 27 62 50 38 50 25 C 50 12 41 2 27 2 Z';

export const PRO_OFFERING_PIN_ANCHOR = { x: 0.5, y: 62 / VIEWBOX_H };

export function ProOfferingPin({ offering }: ProOfferingPinProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  return (
    <View style={styles.wrapper}>
      <Svg width={PIN_WIDTH} height={PIN_HEIGHT} viewBox={`0 0 ${VIEWBOX_W} ${VIEWBOX_H}`}>
        <Path
          d={PIN_PATH}
          fill={colors.pinProBackground}
          stroke={colors.pinBorder}
          strokeWidth={2}
          strokeOpacity={0.55}
          strokeLinejoin="round"
        />
        <Circle
          cx={27}
          cy={24}
          r={18.5}
          fill={colors.pinBackground}
          stroke={colors.pinBorder}
          strokeWidth={1.5}
          strokeOpacity={0.95}
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
    shadowOffset: { width: 0, height: 5 },
    shadowOpacity: 0.6,
    shadowRadius: 6,
    elevation: 10,
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
