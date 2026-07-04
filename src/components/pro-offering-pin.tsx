import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import Svg, { Path, Rect } from 'react-native-svg';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { getSportIcon } from '@/constants/sport-icons';
import { type ProOffering } from '@/services/pro-offering-service';

interface ProOfferingPinProps {
  offering: ProOffering;
}

// Pin system v4.1 (2026-07-04) — the RA follows the UA's exact pin grammar
// (colored frame → ivory plate → sport emoji, soft rounded point) so all three
// markers share one soul; only the HEAD SHAPE and frame color differ:
//   UA = round teardrop, frame = time-status color (peer outing)
//   RA = rounded-SQUARE pin, frame = pro-blue (pro-led outing)
//   PP = pushpin, blue disc + needle (the pro's storefront)
// Shape says "offering ≠ sortie" at a glance; blue ties RA to the PP family.
// No "PRO" text — the blue carries that.

const VIEWBOX_W = 44;
const VIEWBOX_H = 52;
const PIN_WIDTH = 36;
const PIN_HEIGHT = Math.round((PIN_WIDTH * VIEWBOX_H) / VIEWBOX_W);

// Squircle head fusing into a short soft point at (22,50) — same gentle taper
// language as the UA teardrop, but on a square body.
const BODY_PATH =
  'M 12 2 L 32 2 Q 42 2 42 12 L 42 27 Q 42 37 33 38.5 C 27.5 40 23.5 46.5 22 50 C 20.5 46.5 16.5 40 11 38.5 Q 2 37 2 27 L 2 12 Q 2 2 12 2 Z';

export const PRO_OFFERING_PIN_ANCHOR = { x: 0.5, y: 50 / VIEWBOX_H };

// Ivory plate (viewbox) — the emoji centers on it.
const PLATE = { x: 5.5, y: 5.5, w: 33, h: 29, rx: 8 };

export function ProOfferingPin({ offering }: ProOfferingPinProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  return (
    <View style={styles.wrapper}>
      <Svg width={PIN_WIDTH} height={PIN_HEIGHT} viewBox={`0 0 ${VIEWBOX_W} ${VIEWBOX_H}`}>
        <Path
          d={BODY_PATH}
          fill={colors.pinProBackground}
          stroke={colors.pinBorder}
          strokeWidth={2}
          strokeOpacity={0.55}
          strokeLinejoin="round"
        />
        <Rect
          x={PLATE.x}
          y={PLATE.y}
          width={PLATE.w}
          height={PLATE.h}
          rx={PLATE.rx}
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
    left: (PLATE.x / VIEWBOX_W) * PIN_WIDTH,
    top: (PLATE.y / VIEWBOX_H) * PIN_HEIGHT,
    width: (PLATE.w / VIEWBOX_W) * PIN_WIDTH,
    height: (PLATE.h / VIEWBOX_H) * PIN_HEIGHT,
    alignItems: 'center',
    justifyContent: 'center',
  },
  icon: {
    // Same emoji-as-hero sizing rationale as the UA pin.
    fontSize: 16,
  },
});
