import { useMemo } from 'react';
import { View, Text, Image, StyleSheet } from 'react-native';
import Svg, { Path } from 'react-native-svg';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';

interface ProPinProps {
  displayName: string;
  pinImageUrl?: string | null;
}

// Visually distinct from the activity pin (teardrop) and the offering
// pin (hexagon). Pro pins are square-shouldered badges — reads as
// "permanent business storefront". Anchored on the bottom edge so the
// pin sits on the geographic point.
//
// Content inside the badge is either the pro's first initial
// (default) or a square photo when pin_image_url is set.

const VIEWBOX_W = 50;
const VIEWBOX_H = 46;
// Shrunk from 50 to 36 to match the activity/offering pins' lighter
// footprint. The image clip below is ratio-based so it scales with
// the new wrapper size — pin-image overlay still covers the square
// edge to edge.
const PIN_WIDTH = 36;
const PIN_HEIGHT = Math.round((PIN_WIDTH * VIEWBOX_H) / VIEWBOX_W);

const PIN_PATH =
  'M 6 2 L 44 2 Q 48 2 48 6 L 48 42 Q 48 46 44 46 L 6 46 Q 2 46 2 42 L 2 6 Q 2 2 6 2 Z';

export const PRO_PIN_ANCHOR = { x: 0.5, y: 1.0 };

export function ProPin({ displayName, pinImageUrl }: ProPinProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const initial = (displayName.trim().charAt(0) || '?').toUpperCase();

  return (
    <View style={styles.wrapper}>
      {/* SVG renders first (behind). Always filled CTA so the tip stays
          opaque — the image just covers the head area on top. */}
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
      {pinImageUrl ? (
        <View style={styles.imageClip}>
          <Image source={{ uri: pinImageUrl }} style={styles.imageFull} resizeMode="cover" />
        </View>
      ) : (
        <View style={styles.content}>
          <Text style={styles.letter}>{initial}</Text>
        </View>
      )}
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
  content: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    alignItems: 'center',
    justifyContent: 'center',
  },
  letter: {
    color: '#FFFFFF',
    fontSize: 14,
    fontWeight: '800',
    letterSpacing: -0.5,
  },
  // Clipping container that exactly matches the SVG square (viewBox
  // x=2..48, y=2..46, corner radius 4). Ratio-based so it scales
  // proportionally with PIN_WIDTH/HEIGHT — image fills the rendered
  // square edge to edge regardless of the wrapper size.
  imageClip: {
    position: 'absolute',
    top: PIN_HEIGHT * 2 / VIEWBOX_H,
    left: PIN_WIDTH * 2 / VIEWBOX_W,
    width: PIN_WIDTH * (VIEWBOX_W - 4) / VIEWBOX_W,
    height: PIN_HEIGHT * (VIEWBOX_H - 2) / VIEWBOX_H,
    borderRadius: 4 * PIN_WIDTH / VIEWBOX_W,
    overflow: 'hidden',
  },
  imageFull: {
    width: '100%',
    height: '100%',
  },
});
