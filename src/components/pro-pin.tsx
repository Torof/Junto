import { useMemo, type ReactNode } from 'react';
import { View, StyleSheet } from 'react-native';
import { AppText } from '@/components/app-text';
import { Image } from 'expo-image';
import Svg, { Path, Circle, G } from 'react-native-svg';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { SPORT_CATEGORY_COLORS } from '@/utils/sport-category-color';
import {
  PIN_DROP_TIP_Y, PIN_HEAD_CX, PIN_HEAD_CY, PIN_PAD_X, PIN_PAD_Y, PRO_GOLD,
} from '@/constants/pin-style';
import { PinBody } from '@/components/pin-body';

interface ProPinProps {
  displayName: string;
  pinIcon?: string | null;
  // Optional custom logo — fills ONLY the inner disc (circle-cropped); the
  // silhouette never changes, so the map stays coherent whatever the logo.
  pinImageUrl?: string | null;
}

// The pro PAGE pin. Restyle 2026-10-16 (constants/pin-style.ts): the same
// rounded drop as every other pin, in WHITE, with the universe disc inside —
// the family reads as one, white = « a place », colour = « an outing ».
// (The historical pushpin with its needle is gone.)
const DESIGN_W = 54;
const VIEWBOX_W = DESIGN_W + 2 * PIN_PAD_X;
const VIEWBOX_H = 54 + 2 * PIN_PAD_Y;
const DROP_PX = 40;
const SCALE = DROP_PX / DESIGN_W;
const PIN_WIDTH = Math.round(VIEWBOX_W * SCALE);
const PIN_HEIGHT = Math.round(VIEWBOX_H * SCALE);
const DISC_R = 15;
const DISC_D = 2 * DISC_R * SCALE;
const DISC_LEFT = (PIN_HEAD_CX + PIN_PAD_X) * SCALE - DISC_D / 2;
const DISC_TOP = (PIN_HEAD_CY + PIN_PAD_Y) * SCALE - DISC_D / 2;
const GLYPH_SCALE = 0.7;

// Cycling has no clean vector at this size, so it stays a raster — tinted white.
const bikeGlyph = require('../../assets/bike-glyph.png');

export const PRO_PIN_ANCHOR = {
  x: 0.5,
  y: (PIN_DROP_TIP_Y + PIN_PAD_Y) / VIEWBOX_H,
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
    case 'wellness':
      // Yoga figure (MingCute yoga-fill, Apache 2.0) — 24-box centred on the head.
      return (
        <G transform="translate(15 11)">
          <Path d="M8 21v-6.946L7.84 14H4.963a1.5 1.5 0 0 1-1.495-1.385l-.465-6.038a1 1 0 0 1 1.994-.154L5.427 12h2.337l2.11-1.055a1 1 0 0 0 .48-.522l.478-1.197l-4.126-1.27a1 1 0 0 1 .588-1.912l13 4a1 1 0 0 1-.588 1.912l-4.736-1.458l-1.878 2.254c-.319.382-.728.68-1.19.864L10 14.377V21a1 1 0 0 1-2 0M18 5a3 3 0 1 1-6 0a3 3 0 0 1 6 0" fill={white} />
        </G>
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

  return (
    <View style={styles.wrapper}>
      <Svg width={PIN_WIDTH} height={PIN_HEIGHT} viewBox={`${-PIN_PAD_X} ${-PIN_PAD_Y} ${VIEWBOX_W} ${VIEWBOX_H}`}>
        <PinBody fill={colors.pinBackground} outline={PRO_GOLD} />
        {discColor && <Circle cx={PIN_HEAD_CX} cy={PIN_HEAD_CY} r={DISC_R} fill={discColor} />}
        {glyph && (
          <G transform={`translate(${PIN_HEAD_CX} ${PIN_HEAD_CY}) scale(${GLYPH_SCALE}) translate(-${PIN_HEAD_CX} -${PIN_HEAD_CY})`}>{glyph}</G>
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
            <AppText style={styles.letter}>{initial}</AppText>
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
