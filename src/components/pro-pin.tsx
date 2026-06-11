import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import Svg, { Path, Circle } from 'react-native-svg';
import { Image } from 'expo-image';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';

interface ProPinProps {
  displayName: string;
  pinImageUrl?: string | null;
}

// Pin system v3.1 (2026-06-11): a literal pushpin — round photo head
// on a thin metal needle, "pinned to the map". Scott's call: the v2/v3
// circle-with-triangle-tail read as a speech bubble; a pushpin says
// "permanent establishment", which is exactly what a storefront is.
// Pro-badge blue ring around the head matches the RA teardrop frames.
//
// Content: the pro's pin image clipped in the head, or their first
// initial as fallback.

const VIEWBOX_W = 54;
const VIEWBOX_H = 70;
// Head Ø unchanged from the 42-width era ("small and big enough");
// the needle adds height below it.
const PIN_WIDTH = 42;
const PIN_HEIGHT = Math.round((PIN_WIDTH * VIEWBOX_H) / VIEWBOX_W);

// Head: circle c(27,23) r21 (y 2..44). Needle: slim taper from under
// the head down to the tip at (27,67) — the geographic anchor. The top
// of the needle tucks 1 unit behind the head so the joint is hidden.
const NEEDLE_PATH = 'M 25.2 43 L 27 67 L 28.8 43 Z';

// Geometry in render units, for clipping the photo.
const SCALE = PIN_WIDTH / VIEWBOX_W;
const CIRCLE_CX = 27 * SCALE;
const CIRCLE_CY = 23 * SCALE;
// Near-full-bleed photo — inset only 1.5 viewBox units, just enough
// for the ring to stay visible.
const PHOTO_R = 19.5 * SCALE;

export const PRO_PIN_ANCHOR = { x: 0.5, y: 67 / VIEWBOX_H };

export function ProPin({ displayName, pinImageUrl }: ProPinProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
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
          strokeOpacity={0.55}
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
    // Ivory on the saturated pro blue (#3b82f6) — the dark letter was
    // for the lighter indigo era.
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
