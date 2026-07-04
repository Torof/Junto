import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import Svg, { Path, Circle, Rect } from 'react-native-svg';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { getSportIcon } from '@/constants/sport-icons';
import { type ProOffering } from '@/services/pro-offering-service';

interface ProOfferingPinProps {
  offering: ProOffering;
}

// Pin system v4.2 (2026-07-04, Scott's call from the candidates artifact) —
// "la goutte sobre badgée": the RA is the SAME calm teardrop as the UA (stone
// frame → ivory plate → sport emoji) so a dense map stays breathable; the pro
// signal is a small blue briefcase badge at the top-right — blue lives ONLY in
// the badge (a full blue frame screamed at density), briefcase = the same
// glyph as the map's "pros" layer toggle, ring in near-black like every other
// pin outline.

const VIEWBOX_W = 54;
const VIEWBOX_H = 54;
const PIN_WIDTH = 40;
const PIN_HEIGHT = Math.round((PIN_WIDTH * VIEWBOX_H) / VIEWBOX_W);
// viewBox y where the sport emoji is vertically centered (same as the UA pin).
const ICON_CENTER_Y_VBX = 24;

// Identical silhouette to the UA teardrop (activity-pin.tsx).
const PIN_PATH = 'M 27 2 C 13 2 4 12 4 25 C 4 36 21 50 27 52 C 33 50 50 36 50 25 C 50 12 41 2 27 2 Z';

export const PRO_OFFERING_PIN_ANCHOR = { x: 0.5, y: 52 / VIEWBOX_H };

// Badge geometry — kept inside the viewBox so nothing clips.
const BADGE = { cx: 45, cy: 9.5, r: 8 };

export function ProOfferingPin({ offering }: ProOfferingPinProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  return (
    <View style={styles.wrapper}>
      <Svg width={PIN_WIDTH} height={PIN_HEIGHT} viewBox={`0 0 ${VIEWBOX_W} ${VIEWBOX_H}`}>
        <Path
          d={PIN_PATH}
          fill={colors.pinFrame}
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
        {/* Pro badge — blue disc, near-black ring, white briefcase. */}
        <Circle
          cx={BADGE.cx}
          cy={BADGE.cy}
          r={BADGE.r}
          fill={colors.pinProBackground}
          stroke={colors.pinBorder}
          strokeWidth={1.5}
        />
        {/* Briefcase, not padlock: wide flat body, small low handle, and a
            horizontal lid seam (padlocks have a tall arc and no seam). */}
        <Rect x={40.6} y={8.2} width={8.8} height={5.2} rx={1} fill="#FFFFFF" />
        <Path
          d="M 43.7 8.2 V 7.7 a 1.3 1.05 0 0 1 2.6 0 V 8.2"
          stroke="#FFFFFF"
          strokeWidth={1}
          fill="none"
        />
        <Path d="M 40.6 10.5 H 49.4" stroke={colors.pinProBackground} strokeWidth={0.9} />
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
    // Same emoji-on-ivory sizing as the UA pin.
    fontSize: 17,
  },
});
