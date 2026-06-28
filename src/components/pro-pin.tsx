import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import Svg, { Path, Circle } from 'react-native-svg';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { getProPinEmoji } from '@/constants/pro-pin-icons';

interface ProPinProps {
  displayName: string;
  pinIcon?: string | null;
}

// Pin system v4 — the pushpin (round head on a thin needle = "pinned
// establishment") now shows the pro's chosen ENVIRONMENT icon on an ivory
// plate (emoji on ivory for legibility, like the offering/sortie pins),
// inside the pro-blue ring (the family accent). The pro's initial is the
// fallback until they pick an icon. The photo is no longer used on the pin.

const VIEWBOX_W = 54;
const VIEWBOX_H = 70;
const PIN_WIDTH = 42;
const PIN_HEIGHT = Math.round((PIN_WIDTH * VIEWBOX_H) / VIEWBOX_W);

// Head: circle c(27,23) r21. Needle: slim taper to the tip at (27,67) —
// the geographic anchor. The needle top tucks behind the head.
const NEEDLE_PATH = 'M 25.2 43 L 27 67 L 28.8 43 Z';
const SCALE = PIN_WIDTH / VIEWBOX_W;
const CIRCLE_CY = 23 * SCALE;

export const PRO_PIN_ANCHOR = { x: 0.5, y: 67 / VIEWBOX_H };

export function ProPin({ displayName, pinIcon }: ProPinProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const emoji = getProPinEmoji(pinIcon);
  const initial = (displayName.trim().charAt(0) || '?').toUpperCase();

  return (
    <View style={styles.wrapper}>
      <Svg width={PIN_WIDTH} height={PIN_HEIGHT} viewBox={`0 0 ${VIEWBOX_W} ${VIEWBOX_H}`}>
        {/* Needle first — the head renders over its hidden top joint. */}
        <Path d={NEEDLE_PATH} fill={colors.pinBorder} />
        <Circle
          cx={27}
          cy={23}
          r={21}
          fill={colors.pinProBackground}
          stroke={colors.pinBorder}
          strokeWidth={2}
          strokeOpacity={0.9}
        />
        {emoji && (
          // Ivory plate behind the emoji (legibility), leaving a blue ring.
          <Circle
            cx={27}
            cy={23}
            r={16.5}
            fill={colors.pinBackground}
            stroke={colors.pinBorder}
            strokeWidth={1.2}
            strokeOpacity={0.85}
          />
        )}
      </Svg>
      <View style={styles.content}>
        {emoji ? (
          <Text style={styles.emoji}>{emoji}</Text>
        ) : (
          <Text style={styles.letter}>{initial}</Text>
        )}
      </View>
    </View>
  );
}

const createStyles = (colors: AppColors) =>
  StyleSheet.create({
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
    // Centered on the circle, not the full wrapper (the needle would pull a
    // full-height center downward).
    content: {
      position: 'absolute',
      left: 0,
      right: 0,
      top: 0,
      height: CIRCLE_CY * 2,
      alignItems: 'center',
      justifyContent: 'center',
    },
    emoji: {
      fontSize: 17,
    },
    letter: {
      color: colors.pinProBorder,
      fontSize: 14,
      fontWeight: '800',
      letterSpacing: -0.5,
    },
  });
