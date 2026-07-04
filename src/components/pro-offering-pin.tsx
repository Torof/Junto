import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import Svg, { Path, Circle, Rect, Text as SvgText } from 'react-native-svg';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { getSportIcon } from '@/constants/sport-icons';
import { type ProOffering } from '@/services/pro-offering-service';

interface ProOfferingPinProps {
  offering: ProOffering;
}

// Pin system v4.3 (2026-07-04, candidate I from the candidates artifact) —
// "la goutte capsule PRO": the RA is the SAME calm teardrop as the UA (stone
// frame → ivory plate → sport emoji) because RA and UA are both activities;
// the pro signal is a small blue capsule that literally says "PRO" — the same
// word/pill already used on the list cards and the RA drawer header, so the
// map speaks the app's vocabulary. Glyph badges (briefcase, P, pushpin) all
// read ambiguous at 11px; the word needs no learning. Blue lives ONLY in the
// capsule so dense maps stay breathable.

// The viewBox is 4 units wider than the UA's 54 so the capsule can overhang
// the drop's top-right without clipping; the drop itself still spans 0–54.
const VIEWBOX_W = 58;
const VIEWBOX_H = 54;
const PIN_WIDTH = 43; // keeps the drop at the UA's on-screen size (40 × 54/58 ≈ 43)
const PIN_HEIGHT = Math.round((PIN_WIDTH * VIEWBOX_H) / VIEWBOX_W);
// viewBox coords of the emoji center (same drop geometry as the UA pin).
const ICON_CENTER_Y_VBX = 24;
const DROP_SPAN_VBX = 54; // the drop occupies x 0..54; the extra 4 is capsule room

// Identical silhouette to the UA teardrop (activity-pin.tsx).
const PIN_PATH = 'M 27 2 C 13 2 4 12 4 25 C 4 36 21 50 27 52 C 33 50 50 36 50 25 C 50 12 41 2 27 2 Z';

// Tip of the drop is (27, 52) in a 58-wide box.
export const PRO_OFFERING_PIN_ANCHOR = { x: 27 / VIEWBOX_W, y: 52 / VIEWBOX_H };

// "PRO" capsule at the drop's top-right.
const CAPSULE = { x: 35, y: 1.5, w: 22, h: 12, r: 6 };

export function ProOfferingPin({ offering }: ProOfferingPinProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  return (
    <View style={styles.wrapper}>
      <Svg width={PIN_WIDTH} height={PIN_HEIGHT} viewBox={`0 0 ${VIEWBOX_W} ${VIEWBOX_H}`}>
        <Path
          d={PIN_PATH}
          fill={colors.pinProFrame}
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
        {/* "PRO" capsule — blue pill, near-black ring, the word in white. */}
        <Rect
          x={CAPSULE.x}
          y={CAPSULE.y}
          width={CAPSULE.w}
          height={CAPSULE.h}
          rx={CAPSULE.r}
          fill={colors.pinProBackground}
          stroke={colors.pinBorder}
          strokeWidth={1.3}
        />
        <SvgText
          x={CAPSULE.x + CAPSULE.w / 2}
          y={CAPSULE.y + 9.1}
          fontSize={8}
          fontWeight="bold"
          letterSpacing={0.5}
          fill="#FFFFFF"
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
  iconWrap: {
    position: 'absolute',
    top: 0,
    left: 0,
    // Span only the drop's 0..54 portion so the emoji centers on the drop
    // (x=27), not on the capsule-widened 58-unit box.
    width: PIN_WIDTH * (DROP_SPAN_VBX / VIEWBOX_W),
    bottom: PIN_HEIGHT * (1 - 2 * (ICON_CENTER_Y_VBX / VIEWBOX_H)),
    alignItems: 'center',
    justifyContent: 'center',
  },
  icon: {
    // Same emoji-on-ivory sizing as the UA pin.
    fontSize: 17,
  },
});
