import { useMemo, type ReactNode } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { Image } from 'expo-image';
import Svg, { Path, Circle, G } from 'react-native-svg';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { SPORT_CATEGORY_COLORS } from '@/utils/sport-category-color';

interface ProPinProps {
  displayName: string;
  pinIcon?: string | null;
  // Optional custom logo — fills ONLY the inner disc (circle-cropped); the
  // pin silhouette, head and rim never change, so the map stays coherent
  // whatever the logo looks like. Falls back to the universe glyph.
  pinImageUrl?: string | null;
}

// Pin system v4 (taxonomy v2) — the pushpin (round head on a thin needle =
// "pinned establishment") follows the Google place-pin grammar: a WHITE head
// with a grey rim, a needle, and inside it a disc in the pro's UNIVERSE color
// (the same 5-universe palette as activities) carrying a WHITE glyph. The pro
// picks one of 4 universes (mountain · water · air · cycling — no "running":
// no running guides exist). The initial is the fallback before they pick.

const VIEWBOX_W = 54;
const VIEWBOX_H = 70;
const PIN_WIDTH = 42;
const PIN_HEIGHT = Math.round((PIN_WIDTH * VIEWBOX_H) / VIEWBOX_W);
const SCALE = PIN_WIDTH / VIEWBOX_W;
const CIRCLE_CY = 23 * SCALE;

// Needle: slim taper to the tip at (27,67) — the geographic anchor. Filled
// dark (somber), top tucked behind the head.
const NEEDLE_PATH = 'M 24.6 41 L 27 67 L 29.4 41 Z';

// Cycling has no clean vector at this size, so it stays a raster (the shape
// Scott approved) — tinted white over the disc. The others are SVG glyphs.
const bikeGlyph = require('../../assets/bike-glyph.png');

export const PRO_PIN_ANCHOR = { x: 0.5, y: 67 / VIEWBOX_H };

// White glyphs, drawn in the head and scaled 0.8 around the center (27,23).
function glyphFor(key: string, white: string): ReactNode {
  switch (key) {
    case 'mountain':
      return <Path d="M 15 32 L 23 16 L 28 23 L 32 18 L 39 32 Z" fill={white} />;
    case 'water':
      return (
        <Path
          d="M 27 14 C 27 14 19 25 19 29.5 A 8 8 0 1 0 35 29.5 C 35 25 27 14 27 14 Z"
          fill={white}
        />
      );
    case 'air':
      return (
        <>
          <Path
            d="M 15.5 21 C 12 21 12 15.5 16 15.2 C 16 10 23.5 9 25 13.5 C 29.5 11.8 33 15.5 30.5 19 C 33 19.6 32.5 21 30 21 Z"
            fill={white}
          />
          <Path
            d="M 17 28 H 34 a 2.4 2.4 0 1 0 -2.4 -2.4"
            stroke={white}
            strokeWidth={1.3}
            strokeLinecap="round"
            fill="none"
          />
          <Path
            d="M 19 35 H 31 a 2.0 2.0 0 1 0 -2.0 -2.0"
            stroke={white}
            strokeWidth={1.3}
            strokeLinecap="round"
            fill="none"
          />
        </>
      );
    default:
      return null; // cycling -> raster overlay
  }
}

export function ProPin({ displayName, pinIcon, pinImageUrl }: ProPinProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const hasLogo = !!pinImageUrl;
  const discColor = !hasLogo && pinIcon ? SPORT_CATEGORY_COLORS[pinIcon] : undefined;
  const white = colors.pinProBorder;
  const glyph = !hasLogo && pinIcon ? glyphFor(pinIcon, white) : null;
  const isBike = !hasLogo && pinIcon === 'cycling';
  const initial = (displayName.trim().charAt(0) || '?').toUpperCase();

  return (
    <View style={styles.wrapper}>
      <Svg width={PIN_WIDTH} height={PIN_HEIGHT} viewBox={`0 0 ${VIEWBOX_W} ${VIEWBOX_H}`}>
        {/* Needle first — the head renders over its hidden top joint. */}
        <Path d={NEEDLE_PATH} fill={colors.pinBorder} />
        <Circle cx={27} cy={23} r={21} fill={colors.pinBackground} stroke={colors.pinProRim} strokeWidth={1.3} />
        {discColor && <Circle cx={27} cy={23} r={18.5} fill={discColor} />}
        {glyph && (
          <G transform="translate(27 23) scale(0.8) translate(-27 -23)">{glyph}</G>
        )}
      </Svg>
      {/* Custom logo — circle-cropped over the inner disc; the head/rim
          stay Junto's whatever the logo is. */}
      {hasLogo && (
        <View style={styles.content} pointerEvents="none">
          <Image source={{ uri: pinImageUrl }} style={styles.logo} contentFit="cover" />
        </View>
      )}
      {/* cycling = raster bike (white tint); no icon = the pro's initial */}
      {!hasLogo && (isBike || !pinIcon) && (
        <View style={styles.content} pointerEvents="none">
          {isBike ? (
            <Image source={bikeGlyph} tintColor={white} style={styles.bike} contentFit="contain" />
          ) : (
            <Text style={styles.letter}>{initial}</Text>
          )}
        </View>
      )}
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
    // Centered on the head circle, not the full wrapper (the needle would
    // pull a full-height center downward).
    content: {
      position: 'absolute',
      left: 0,
      right: 0,
      top: 0,
      height: CIRCLE_CY * 2,
      alignItems: 'center',
      justifyContent: 'center',
    },
    bike: {
      width: 22,
      height: 14,
    },
    // Inner-disc size (r 18.5 in the 54-unit viewBox, scaled to dp).
    logo: {
      width: 37 * SCALE,
      height: 37 * SCALE,
      borderRadius: (37 * SCALE) / 2,
    },
    letter: {
      color: colors.pinBorder,
      fontSize: 14,
      fontWeight: '800',
      letterSpacing: -0.5,
    },
  });
