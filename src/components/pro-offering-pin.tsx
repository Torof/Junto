import { useMemo } from 'react';
import { View, StyleSheet } from 'react-native';
import { AppText } from '@/components/app-text';
import Svg, { Rect, G, Text as SvgText } from 'react-native-svg';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { getSportIcon } from '@/constants/sport-icons';
import { SportIcon } from '@/components/sport-icon';
import { hasSportIcon } from '@/constants/sport-icon-svgs';
import { type ProOffering } from '@/services/pro-offering-service';
import {
  PIN_DROP_TIP_Y, PIN_HEAD_CX, PIN_HEAD_CY, PIN_PAD_X, PIN_PAD_Y, PRO_GOLD, PRO_GOLD_INK,
} from '@/constants/pin-style';
import { PinBody } from '@/components/pin-body';
import { sportCategoryColor } from '@/utils/sport-category-color';

interface ProOfferingPinProps {
  offering: ProOffering;
}

// The pro outing: the same rounded drop as the activity pin, in the sport's
// universe colour, with the gold outline and the gold « PRO » capsule at the
// drop's top-left (labels anchor to the pin's right) — 2026-10-25.
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
  // 2026-10-25: the body takes the sport's universe colour, like every outing —
  // gold (outline + capsule) is what says « pro », not a blue of its own.
  const body = sportCategoryColor(offering.sport_category, colors.cta);

  return (
    <View style={styles.wrapper}>
      <Svg width={PIN_WIDTH} height={PIN_HEIGHT} viewBox={`${-PIN_PAD_X} ${-PIN_PAD_Y} ${VIEWBOX_W} ${VIEWBOX_H}`}>
        <G transform={`translate(${DROP_OFFSET} 0)`}>
          <PinBody fill={body} outline={PRO_GOLD} />
        </G>
        {/* « PRO » capsule: gold, ink text — the pro badge of the pages (2026-10-25). */}
        <Rect
          x={CAPSULE.x} y={CAPSULE.y} width={CAPSULE.w} height={CAPSULE.h} rx={CAPSULE.r}
          fill={PRO_GOLD}
        />
        <SvgText
          x={CAPSULE.x + CAPSULE.w / 2}
          y={CAPSULE.y + 9.1}
          fontSize={8}
          fontWeight="bold"
          letterSpacing={0.5}
          fill={PRO_GOLD_INK}
          textAnchor="middle"
        >
          PRO
        </SvgText>
      </Svg>
      <View style={styles.plateClip}>
        {hasSportIcon(offering.sport_key) ? (
          <SportIcon sportKey={offering.sport_key} size={24} color={colors.onCta} />
        ) : (
          <AppText style={styles.icon}>{getSportIcon(offering.sport_key)}</AppText>
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
