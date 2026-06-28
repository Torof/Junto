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

// Pin system v4 — shape encodes kind (square = pro offering, vs teardrop
// peer sortie, vs pushpin pro page). The body + pointer are ONE continuous
// path so the tail reads as fused (not a triangle stuck under a box). The
// ivory plate hugs the body with a thin frame, and a full-width "PRO"
// banner is dropped on top to make the commercial / pro-led nature explicit
// (no price — Junto isn't a payment platform).

const VIEWBOX_W = 52;
const VIEWBOX_H = 68;
const PIN_WIDTH = 48;
const PIN_HEIGHT = Math.round((PIN_WIDTH * VIEWBOX_H) / VIEWBOX_W);

// Single silhouette: rounded-top square tapering to a fused point at (26,64).
const BODY_PATH =
  'M 16 14 L 36 14 Q 46 14 46 24 L 46 44 Q 46 49 41 51 L 26 64 L 11 51 Q 6 49 6 44 L 6 24 Q 6 14 16 14 Z';

// Pointer tip = the point on the coordinate.
export const PRO_OFFERING_PIN_ANCHOR = { x: 0.5, y: 64 / VIEWBOX_H };

// Ivory plate region (viewbox) — thin frame around it (padding ≈ 3).
const PLATE = { x: 9, y: 25, w: 34, h: 23 };

export function ProOfferingPin({ offering }: ProOfferingPinProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  return (
    <View style={styles.wrapper}>
      <Svg width={PIN_WIDTH} height={PIN_HEIGHT} viewBox={`0 0 ${VIEWBOX_W} ${VIEWBOX_H}`}>
        {/* body + fused tail, one path */}
        <Path
          d={BODY_PATH}
          fill={colors.pinProBackground}
          stroke={colors.pinBorder}
          strokeWidth={2}
          strokeOpacity={0.55}
          strokeLinejoin="round"
        />
        {/* ivory plate — thin frame, hugs the body */}
        <Rect
          x={PLATE.x}
          y={PLATE.y}
          width={PLATE.w}
          height={PLATE.h}
          rx={6}
          fill={colors.pinBackground}
          stroke={colors.pinBorder}
          strokeWidth={1.2}
          strokeOpacity={0.9}
        />
        {/* PRO banner — full body width, dropped on top */}
        <Rect x={6} y={3} width={40} height={18} rx={6} fill={colors.pinBorder} />
        <SvgText
          x={26}
          y={15.5}
          fontSize={11}
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
  // Centred on the ivory plate.
  iconWrap: {
    position: 'absolute',
    left: (PLATE.x / VIEWBOX_W) * PIN_WIDTH,
    top: (PLATE.y / VIEWBOX_H) * PIN_HEIGHT,
    width: (PLATE.w / VIEWBOX_W) * PIN_WIDTH,
    height: (PLATE.h / VIEWBOX_H) * PIN_HEIGHT,
    alignItems: 'center',
    justifyContent: 'center',
  },
  icon: {
    fontSize: 17,
  },
});
