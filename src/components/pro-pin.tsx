import { useMemo, type ReactNode } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { Image } from 'expo-image';
import Svg, { Path, Circle, G, Defs, Filter, FeDropShadow, ClipPath } from 'react-native-svg';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { SPORT_CATEGORY_COLORS } from '@/utils/sport-category-color';
import {
  PIN_STYLE, PIN_DROP_PATH, PIN_DROP_TIP_Y, PIN_HEAD_CX, PIN_HEAD_CY, PIN_PAD_X, PIN_PAD_Y, PIN_SHADOW,
} from '@/constants/pin-style';

interface ProPinProps {
  displayName: string;
  pinIcon?: string | null;
  // Optional custom logo — fills ONLY the inner disc (circle-cropped); the
  // silhouette never changes, so the map stays coherent whatever the logo.
  pinImageUrl?: string | null;
}

// The pro PAGE pin. Restyle 2026-10-16 (constants/pin-style.ts):
//   A — the pushpin softened: white head without rim, short needle with a
//       rounded end, universe disc + white glyph, soft SVG shadow.
//   B — the same rounded drop as every other pin, in WHITE, with the universe
//       disc inside: the family reads as one, white = « a place », colour =
//       « an outing ».
const DESIGN_W = 54;
const VIEWBOX_W = DESIGN_W + 2 * PIN_PAD_X;
const NEEDLE_TIP_Y = 58;
const VIEWBOX_H = (PIN_STYLE === 'A' ? NEEDLE_TIP_Y + 4 : 54) + 2 * PIN_PAD_Y;
const DROP_PX = PIN_STYLE === 'A' ? 42 : 40;
const SCALE = DROP_PX / DESIGN_W;
const PIN_WIDTH = Math.round(VIEWBOX_W * SCALE);
const PIN_HEIGHT = Math.round(VIEWBOX_H * SCALE);
const DISC_R = PIN_STYLE === 'A' ? 17.5 : 15;
const DISC_D = 2 * DISC_R * SCALE;
const DISC_LEFT = (PIN_HEAD_CX + PIN_PAD_X) * SCALE - DISC_D / 2;
const DISC_TOP = (PIN_HEAD_CY + PIN_PAD_Y) * SCALE - DISC_D / 2;

// Short needle with a rounded end (A only).
const NEEDLE_PATH = `M 24.4 42 L 25.6 ${NEEDLE_TIP_Y - 2} C 25.8 ${NEEDLE_TIP_Y} 28.2 ${NEEDLE_TIP_Y} 28.4 ${NEEDLE_TIP_Y - 2} L 29.6 42 Z`;

// Cycling has no clean vector at this size, so it stays a raster — tinted white.
const bikeGlyph = require('../../assets/bike-glyph.png');

export const PRO_PIN_ANCHOR = {
  x: 0.5,
  y: ((PIN_STYLE === 'A' ? NEEDLE_TIP_Y : PIN_DROP_TIP_Y) + PIN_PAD_Y) / VIEWBOX_H,
};

// White glyphs, drawn in the head and scaled around its centre (27, 23).
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
          <Path d="M 17 28 H 34 a 2.4 2.4 0 1 0 -2.4 -2.4" stroke={white} strokeWidth={1.3} strokeLinecap="round" fill="none" />
          <Path d="M 19 35 H 31 a 2.0 2.0 0 1 0 -2.0 -2.0" stroke={white} strokeWidth={1.3} strokeLinecap="round" fill="none" />
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
  const white = colors.onCta;
  const glyph = !hasLogo && pinIcon ? glyphFor(pinIcon, white) : null;
  const isBike = !hasLogo && pinIcon === 'cycling';
  const initial = (displayName.trim().charAt(0) || '?').toUpperCase();
  const glyphScale = PIN_STYLE === 'A' ? 0.8 : 0.7;

  return (
    <View style={styles.wrapper}>
      <Svg width={PIN_WIDTH} height={PIN_HEIGHT} viewBox={`${-PIN_PAD_X} ${-PIN_PAD_Y} ${VIEWBOX_W} ${VIEWBOX_H}`}>
        <Defs>
          <Filter id="pinShadow" x="-30%" y="-30%" width="160%" height="170%">
            <FeDropShadow dx={PIN_SHADOW.dx} dy={PIN_SHADOW.dy} stdDeviation={PIN_SHADOW.blur} floodColor={PIN_SHADOW.color} floodOpacity={PIN_SHADOW.opacity} />
          </Filter>
          <ClipPath id="pinDisc"><Circle cx={PIN_HEAD_CX} cy={PIN_HEAD_CY} r={DISC_R} /></ClipPath>
        </Defs>
        {PIN_STYLE === 'A' ? (
          <G filter="url(#pinShadow)">
            <Path d={NEEDLE_PATH} fill={colors.pinBorder} />
            <Circle cx={PIN_HEAD_CX} cy={PIN_HEAD_CY} r={21} fill={colors.pinBackground} />
          </G>
        ) : (
          <Path d={PIN_DROP_PATH} fill={colors.pinBackground} filter="url(#pinShadow)" />
        )}
        {discColor && <Circle cx={PIN_HEAD_CX} cy={PIN_HEAD_CY} r={DISC_R} fill={discColor} />}
        {glyph && (
          <G transform={`translate(${PIN_HEAD_CX} ${PIN_HEAD_CY}) scale(${glyphScale}) translate(-${PIN_HEAD_CX} -${PIN_HEAD_CY})`}>{glyph}</G>
        )}
      </Svg>
      {/* Custom logo — circle-cropped over the inner disc. */}
      {hasLogo && (
        <View style={styles.disc} pointerEvents="none">
          <Image source={{ uri: pinImageUrl }} style={styles.logo} contentFit="cover" />
        </View>
      )}
      {/* cycling = raster bike (white tint); no icon = the pro's initial */}
      {!hasLogo && (isBike || !pinIcon) && (
        <View style={styles.disc} pointerEvents="none">
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
    },
    // Centred on the head disc, in screen px.
    disc: {
      position: 'absolute',
      left: DISC_LEFT,
      top: DISC_TOP,
      width: DISC_D,
      height: DISC_D,
      borderRadius: DISC_D / 2,
      overflow: 'hidden',
      alignItems: 'center',
      justifyContent: 'center',
    },
    bike: {
      width: DISC_D * 0.82,
      height: DISC_D * 0.52,
    },
    logo: {
      width: DISC_D,
      height: DISC_D,
      borderRadius: DISC_D / 2,
    },
    letter: {
      color: colors.pinBorder,
      fontSize: 14,
      fontWeight: '800',
      letterSpacing: -0.5,
    },
  });
