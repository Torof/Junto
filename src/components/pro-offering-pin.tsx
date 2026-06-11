import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import Svg, { Path, Rect } from 'react-native-svg';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { getSportIcon } from '@/constants/sport-icons';
import { type ProOffering } from '@/services/pro-offering-service';

// Pin system v2 (2026-06-11): rounded-square card with a tail.
// The pro family signature is luminance inversion — peer pins are
// light-bodied (pinBackground), pro pins are dark navy
// (pinProBackground) with a light outline. Silhouette categorizes
// (square card = offer, teardrop = event, circle = pro identity),
// the dark/light split affiliates, and the sport emoji stays the
// single scan target across both worlds: a user hunting kayak scans
// for one glyph, the body tells them peer vs pro.

interface ProOfferingPinProps {
  offering: ProOffering;
}

const VIEWBOX_W = 54;
const VIEWBOX_H = 64;
// Same footprint as the activity teardrop — sizes are locked.
const PIN_WIDTH = 40;
const PIN_HEIGHT = Math.round((PIN_WIDTH * VIEWBOX_H) / VIEWBOX_W);
// Geometric center of the card body (y range 12..54).
const ICON_CENTER_Y_VBX = 33;

// Rounded-square card (x 6..48, y 12..54, r 8) with a small tail
// down to (27, 62) — the geographic anchor, matching the teardrop's
// registration so the swap is drop-in.
const PIN_PATH =
  'M 14 12 L 40 12 Q 48 12 48 20 L 48 46 Q 48 54 40 54 L 33 54 L 27 62 L 21 54 L 14 54 Q 6 54 6 46 L 6 20 Q 6 12 14 12 Z';

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
        {/* Ivory content plate — the indigo reads as a frame (same
            grammar as the PP circle ringing its photo) and the sport
            emoji gets full contrast on light ground. Outline + plate
            match the UA teardrop exactly; only the slim indigo frame
            is new information. */}
        <Rect x={9} y={15} width={36} height={36} rx={6} fill={colors.pinBackground} />
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
    fontSize: 14,
  },
});
