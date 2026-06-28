import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import Svg, { Path, Rect, Text as SvgText } from 'react-native-svg';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { getSportIcon } from '@/constants/sport-icons';
import { type ProOffering } from '@/services/pro-offering-service';

interface ProOfferingPinProps {
  offering: ProOffering;
}

// Pin system v4 (2026-06): a pro offering is NOT a peer sortie, so it no
// longer borrows the teardrop. SHAPE encodes kind:
//   teardrop  = peer sortie (event)
//   SQUARE    = pro offering (commercial, pro-led activity)  ← this
//   pushpin   = pro page (the establishment)
// The blue rounded-square body + sport emoji reads as "a bookable service",
// and a small "PRO" chip makes the commercial/pro-led nature explicit at a
// glance (no price — Junto isn't a payment platform; the chip just signals
// "encadré par un pro"). Page vs offering can now share a sport and stay
// unmistakable, because the silhouette differs.

const VIEWBOX_W = 64;
const VIEWBOX_H = 66;
const PIN_WIDTH = 60;
const PIN_HEIGHT = Math.round((PIN_WIDTH * VIEWBOX_H) / VIEWBOX_W);

// Pointer tip (the point that sits on the coordinate). Body is centered at
// x=28; the PRO chip overhangs to the right, so the anchor x is the BODY
// centre, not the viewbox centre.
export const PRO_OFFERING_PIN_ANCHOR = { x: 28 / VIEWBOX_W, y: 64 / VIEWBOX_H };

export function ProOfferingPin({ offering }: ProOfferingPinProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  return (
    <View style={styles.wrapper}>
      <Svg width={PIN_WIDTH} height={PIN_HEIGHT} viewBox={`0 0 ${VIEWBOX_W} ${VIEWBOX_H}`}>
        {/* bottom pointer */}
        <Path d="M 20 50 L 36 50 L 28 64 Z" fill={colors.pinProBackground} />
        {/* square body */}
        <Rect
          x={8}
          y={12}
          width={40}
          height={40}
          rx={11}
          fill={colors.pinProBackground}
          stroke={colors.pinBorder}
          strokeWidth={2}
          strokeOpacity={0.55}
        />
        {/* ivory plate behind the sport emoji */}
        <Rect
          x={14}
          y={18}
          width={28}
          height={28}
          rx={8}
          fill={colors.pinBackground}
          stroke={colors.pinBorder}
          strokeWidth={1.5}
          strokeOpacity={0.95}
        />
        {/* PRO chip — overhangs the top-right corner */}
        <Rect x={37} y={2} width={25} height={15} rx={4} fill={colors.pinBorder} />
        <SvgText
          x={49.5}
          y={12.6}
          fontSize={9}
          fontWeight="bold"
          fill={colors.pinBackground}
          textAnchor="middle"
        >
          PRO
        </SvgText>
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
  // Centred on the ivory plate (viewbox x 14→42, y 18→46) scaled to px.
  iconWrap: {
    position: 'absolute',
    left: (14 / VIEWBOX_W) * PIN_WIDTH,
    top: (18 / VIEWBOX_H) * PIN_HEIGHT,
    width: (28 / VIEWBOX_W) * PIN_WIDTH,
    height: (28 / VIEWBOX_H) * PIN_HEIGHT,
    alignItems: 'center',
    justifyContent: 'center',
  },
  icon: {
    fontSize: 16,
  },
});
