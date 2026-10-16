import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import Svg, { Path, Circle, Rect, G, Text as SvgText, Defs, Filter, FeGaussianBlur } from 'react-native-svg';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { getSportIcon } from '@/constants/sport-icons';
import { SportIcon } from '@/components/sport-icon';
import { hasSportIcon } from '@/constants/sport-icon-svgs';
import { type ProOffering } from '@/services/pro-offering-service';
import {
  PIN_STYLE, PIN_DROP_PATH, PIN_DROP_TIP_Y, PIN_HEAD_CX, PIN_HEAD_CY, PIN_PAD_X, PIN_PAD_Y, PIN_SHADOW,
} from '@/constants/pin-style';

interface ProOfferingPinProps {
  offering: ProOffering;
}

// The pro outing: the same rounded drop as the activity pin, in the pro blue
// (one colour, one meaning — the PRO capsule, the cards), with the « PRO »
// capsule at the drop's top-left (labels anchor to the pin's right).
// Restyle 2026-10-16: no ink outline, soft SVG shadow, rounded tip.
const DESIGN_W = 54;
const DROP_OFFSET = 4; // room for the capsule on the left
const VIEWBOX_W = DESIGN_W + DROP_OFFSET + 2 * PIN_PAD_X;
const VIEWBOX_H = 54 + 2 * PIN_PAD_Y;
const DROP_PX = 40;
const SCALE = DROP_PX / DESIGN_W;
const PIN_WIDTH = Math.round(VIEWBOX_W * SCALE);
const PIN_HEIGHT = Math.round(VIEWBOX_H * SCALE);
const PLATE_R = 17;
const PLATE_D = 2 * PLATE_R * SCALE;
const PLATE_LEFT = (PIN_HEAD_CX + DROP_OFFSET + PIN_PAD_X) * SCALE - PLATE_D / 2;
const PLATE_TOP = (PIN_HEAD_CY + PIN_PAD_Y) * SCALE - PLATE_D / 2;

export const PRO_OFFERING_PIN_ANCHOR = {
  x: (PIN_HEAD_CX + DROP_OFFSET + PIN_PAD_X) / VIEWBOX_W,
  y: (PIN_DROP_TIP_Y + PIN_PAD_Y) / VIEWBOX_H,
};

const CAPSULE = { x: 1, y: 1.5, w: 22, h: 12, r: 6 };

export function ProOfferingPin({ offering }: ProOfferingPinProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const blue = colors.pinProBackground;

  return (
    <View style={styles.wrapper}>
      <Svg width={PIN_WIDTH} height={PIN_HEIGHT} viewBox={`${-PIN_PAD_X} ${-PIN_PAD_Y} ${VIEWBOX_W} ${VIEWBOX_H}`}>
        <Defs>
          <Filter id="pinBlur" x="-30%" y="-30%" width="160%" height="170%">
            <FeGaussianBlur stdDeviation={PIN_SHADOW.blur} />
          </Filter>
        </Defs>
        <G transform={`translate(${DROP_OFFSET} 0)`}>
          <Path
            d={PIN_DROP_PATH}
            fill={PIN_SHADOW.color}
            opacity={PIN_SHADOW.opacity}
            transform={`translate(${PIN_SHADOW.dx} ${PIN_SHADOW.dy})`}
            filter="url(#pinBlur)"
          />
          <Path d={PIN_DROP_PATH} fill={blue} />
          {PIN_STYLE === 'A' && <Circle cx={PIN_HEAD_CX} cy={PIN_HEAD_CY} r={PLATE_R} fill={colors.pinBackground} />}
        </G>
        {/* « PRO » capsule: blue on ivory in A, white on the blue body in B. */}
        <Rect
          x={CAPSULE.x} y={CAPSULE.y} width={CAPSULE.w} height={CAPSULE.h} rx={CAPSULE.r}
          fill={PIN_STYLE === 'B' ? colors.pinBackground : blue}
        />
        <SvgText
          x={CAPSULE.x + CAPSULE.w / 2}
          y={CAPSULE.y + 9.1}
          fontSize={8}
          fontWeight="bold"
          letterSpacing={0.5}
          fill={PIN_STYLE === 'B' ? blue : colors.onCta}
          textAnchor="middle"
        >
          PRO
        </SvgText>
      </Svg>
      <View style={styles.plateClip}>
        {hasSportIcon(offering.sport_key) ? (
          <SportIcon sportKey={offering.sport_key} size={PIN_STYLE === 'B' ? 24 : 22} color={PIN_STYLE === 'B' ? colors.onCta : undefined} />
        ) : (
          <Text style={styles.icon}>{getSportIcon(offering.sport_key)}</Text>
        )}
      </View>
    </View>
  );
}

const createStyles = (_colors: AppColors) => StyleSheet.create({
  wrapper: {
    width: PIN_WIDTH,
    height: PIN_HEIGHT,
    overflow: 'visible',
  },
  plateClip: {
    position: 'absolute',
    left: PLATE_LEFT,
    top: PLATE_TOP,
    width: PLATE_D,
    height: PLATE_D,
    borderRadius: PLATE_D / 2,
    overflow: 'hidden',
    alignItems: 'center',
    justifyContent: 'center',
  },
  icon: {
    fontSize: 17,
  },
});
