import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import Svg, { Path } from 'react-native-svg';
import { Image } from 'expo-image';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';

interface ProPinProps {
  displayName: string;
  pinImageUrl?: string | null;
}

// Pin system v2 (2026-06-11): circle with a tail — an avatar planted
// on the map. Circle = identity ("this pro is established here"),
// mirroring the circular avatars used everywhere in the app. Pro
// family signature: dark navy body + light outline (luminance
// inversion of the peer pins). PP is deliberately the quietest pin —
// users scan for offerings (RA), not for specific pros.
//
// Content: the pro's pin image clipped in the circle, or their first
// initial as fallback.

const VIEWBOX_W = 54;
const VIEWBOX_H = 60;
// Bumped 36 → 42 (2026-06-11): the photo-in-circle read as cramped at
// 36. PP stays the quiet pin through its treatment, not its size.
const PIN_WIDTH = 42;
const PIN_HEIGHT = Math.round((PIN_WIDTH * VIEWBOX_H) / VIEWBOX_W);

// Circle c(27,25) r21 with a tail to (27,56). The tail meets the
// circle at ±20° off vertical; the arc travels the long way over the
// top (large-arc, counterclockwise in y-down coords).
const PIN_PATH = 'M 19.8 44.7 L 27 56 L 34.2 44.7 A 21 21 0 1 0 19.8 44.7 Z';

// Circle geometry in render units, for clipping the photo.
const SCALE = PIN_WIDTH / VIEWBOX_W;
const CIRCLE_CX = 27 * SCALE;
const CIRCLE_CY = 25 * SCALE;
// Near-full-bleed photo — inset only 1.5 viewBox units, just enough
// for the light outline to ring it.
const PHOTO_R = 19.5 * SCALE;

export const PRO_PIN_ANCHOR = { x: 0.5, y: 56 / VIEWBOX_H };

export function ProPin({ displayName, pinImageUrl }: ProPinProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const initial = (displayName.trim().charAt(0) || '?').toUpperCase();

  return (
    <View style={styles.wrapper}>
      <Svg width={PIN_WIDTH} height={PIN_HEIGHT} viewBox={`0 0 ${VIEWBOX_W} ${VIEWBOX_H}`}>
        <Path
          d={PIN_PATH}
          fill={colors.pinProBackground}
          stroke={colors.pinProBorder}
          strokeWidth={2}
          strokeOpacity={0.9}
          strokeLinejoin="round"
        />
      </Svg>
      {pinImageUrl ? (
        <View style={styles.imageClip}>
          <Image source={{ uri: pinImageUrl }} style={styles.imageFull} contentFit="cover" />
        </View>
      ) : (
        <View style={styles.content}>
          <Text style={styles.letter}>{initial}</Text>
        </View>
      )}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
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
  // Letter fallback — centered on the circle, not the full wrapper
  // (the tail would pull a full-height center downward).
  content: {
    position: 'absolute',
    left: 0,
    right: 0,
    top: 0,
    height: CIRCLE_CY * 2,
    alignItems: 'center',
    justifyContent: 'center',
  },
  letter: {
    color: colors.pinProBorder,
    fontSize: 14,
    fontWeight: '800',
    letterSpacing: -0.5,
  },
  imageClip: {
    position: 'absolute',
    left: CIRCLE_CX - PHOTO_R,
    top: CIRCLE_CY - PHOTO_R,
    width: PHOTO_R * 2,
    height: PHOTO_R * 2,
    borderRadius: PHOTO_R,
    overflow: 'hidden',
  },
  imageFull: {
    width: '100%',
    height: '100%',
  },
});
