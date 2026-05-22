import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import Svg, { Path } from 'react-native-svg';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';

interface ProPinProps {
  displayName: string;
}

// Visually distinct from the activity pin (which is a classic teardrop).
// Pro pins read as "permanent business storefront" — square-shouldered
// badge with a downward chat-bubble-style tip pointing at the location.
// Same anchor pattern as the activity pin so the tip sits exactly on
// the geographic coordinate.

const VIEWBOX_W = 50;
const VIEWBOX_H = 60;
const PIN_WIDTH = 50;
const PIN_HEIGHT = Math.round((PIN_WIDTH * VIEWBOX_H) / VIEWBOX_W);
// y where the letter is visually centered inside the badge head
const LETTER_CENTER_Y_VBX = 22;

// Rounded square (5px radius corners) with a 6-px-wide triangular tip
// pointing down from the bottom-center to (25, 60).
const PIN_PATH =
  'M 6 2 L 44 2 Q 48 2 48 6 L 48 42 Q 48 46 44 46 L 30 46 L 25 60 L 20 46 L 6 46 Q 2 46 2 42 L 2 6 Q 2 2 6 2 Z';

export const PRO_PIN_ANCHOR = { x: 0.5, y: 60 / VIEWBOX_H };

export function ProPin({ displayName }: ProPinProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const initial = (displayName.trim().charAt(0) || '?').toUpperCase();

  return (
    <View style={styles.wrapper}>
      <Svg width={PIN_WIDTH} height={PIN_HEIGHT} viewBox={`0 0 ${VIEWBOX_W} ${VIEWBOX_H}`}>
        <Path
          d={PIN_PATH}
          fill={colors.cta}
          stroke={colors.pinBorder}
          strokeWidth={2}
          strokeOpacity={0.55}
          strokeLinejoin="round"
        />
      </Svg>
      <View style={styles.letterWrap}>
        <Text style={styles.letter}>{initial}</Text>
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
  letterWrap: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: PIN_HEIGHT * (1 - 2 * (LETTER_CENTER_Y_VBX / VIEWBOX_H)),
    alignItems: 'center',
    justifyContent: 'center',
  },
  letter: {
    color: '#FFFFFF',
    fontSize: 20,
    fontWeight: '800',
    letterSpacing: -0.5,
  },
});
