import { useMemo, type ReactNode } from 'react';
import { View, StyleSheet } from 'react-native';
import { AppText } from '@/components/app-text';
import { Image } from 'expo-image';
import Svg, { Path, G, Rect, Text as SvgText, ClipPath, Image as SvgImage } from 'react-native-svg';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { SPORT_CATEGORY_COLORS } from '@/utils/sport-category-color';
import {
  PIN_DROP_TIP_Y, PIN_HEAD_CX, PIN_PAD_X, PIN_PAD_Y, PIN_PRO_CAPSULE, PIN_SHIELD_EDGE, PIN_SHIELD_PATH,
  PRO_GOLD, PRO_GOLD_INK,
} from '@/constants/pin-style';
import { PinBody } from '@/components/pin-body';

interface ProPinProps {
  displayName: string;
  pinIcon?: string | null;
  // Optional custom image — fills the WHOLE shield (clipped to it); the
  // silhouette never changes, so the map stays coherent whatever the image.
  pinImageUrl?: string | null;
}

// The pro PAGE pin (Scott 2026-10-26, mockups « E3 » + « U4 »): a SHIELD —
// « someone », where every outing is a drop — with the gold outline and a
// thin ink edge outside it, and the gold PRO capsule hanging under the tip.
// The pro's pin image fills it; without one, a pale tint of the universe
// with the universe glyph in full colour (pale = a person, full = an outing).
// Same 54-wide design space as the drop, same tip, so labels and anchors hold.
const DESIGN_W = 54;
const VIEWBOX_W = DESIGN_W + 2 * PIN_PAD_X;
const VIEWBOX_H = 54 + 2 * PIN_PAD_Y;
const DROP_PX = 40;
const SCALE = DROP_PX / DESIGN_W;
const PIN_WIDTH = Math.round(VIEWBOX_W * SCALE);
const PIN_HEIGHT = Math.round(VIEWBOX_H * SCALE);
// The glyph sits a touch under the head centre (the shield's weight is high).
const GLYPH_CX = 27;
const GLYPH_CY = 24;
const GLYPH_SCALE = 0.8;
const INNER_R = 15;
const INNER_D = 2 * INNER_R * SCALE;
const INNER_LEFT = (GLYPH_CX + PIN_PAD_X) * SCALE - INNER_D / 2;
const INNER_TOP = (GLYPH_CY + PIN_PAD_Y) * SCALE - INNER_D / 2;
// The image box = the shield's bounding box; `slice` crops it to the shield.
const IMAGE_BOX = { x: 7, y: 3, w: 40, h: 49 };

// Cycling has no clean vector at this size, so it stays a raster — tinted.
const bikeGlyph = require('../../assets/bike-glyph.png');

export const PRO_PIN_ANCHOR = {
  x: 0.5,
  y: (PIN_DROP_TIP_Y + PIN_PAD_Y) / VIEWBOX_H,
};

// The universe at ~20 % over white — the shield's ground without an image.
function tint(hex: string, alpha = 0.2): string {
  const n = parseInt(hex.slice(1), 16);
  const mix = (c: number) => Math.round(255 + (c - 255) * alpha).toString(16).padStart(2, '0');
  return `#${mix((n >> 16) & 255)}${mix((n >> 8) & 255)}${mix(n & 255)}`;
}

// Glyphs drawn in the head and scaled around (27, 23), in the universe colour.
function glyphFor(key: string, color: string): ReactNode {
  switch (key) {
    case 'mountain':
      return <Path d="M 15 32 L 23 16 L 28 23 L 32 18 L 39 32 Z" fill={color} />;
    case 'water':
      return (
        <Path
          d="M 27 14 C 27 14 19 25 19 29.5 A 8 8 0 1 0 35 29.5 C 35 25 27 14 27 14 Z"
          fill={color}
        />
      );
    case 'air':
      return (
        <>
          <Path
            d="M 15.5 21 C 12 21 12 15.5 16 15.2 C 16 10 23.5 9 25 13.5 C 29.5 11.8 33 15.5 30.5 19 C 33 19.6 32.5 21 30 21 Z"
            fill={color}
          />
          <Path d="M 17 28 H 34 a 2.4 2.4 0 1 0 -2.4 -2.4" stroke={color} strokeWidth={1.3} strokeLinecap="round" fill="none" />
          <Path d="M 19 35 H 31 a 2.0 2.0 0 1 0 -2.0 -2.0" stroke={color} strokeWidth={1.3} strokeLinecap="round" fill="none" />
        </>
      );
    case 'wellness':
      // Yoga figure (MingCute yoga-fill, Apache 2.0) — 24-box centred on the head.
      return (
        <G transform="translate(15 11)">
          <Path d="M8 21v-6.946L7.84 14H4.963a1.5 1.5 0 0 1-1.495-1.385l-.465-6.038a1 1 0 0 1 1.994-.154L5.427 12h2.337l2.11-1.055a1 1 0 0 0 .48-.522l.478-1.197l-4.126-1.27a1 1 0 0 1 .588-1.912l13 4a1 1 0 0 1-.588 1.912l-4.736-1.458l-1.878 2.254c-.319.382-.728.68-1.19.864L10 14.377V21a1 1 0 0 1-2 0M18 5a3 3 0 1 1-6 0a3 3 0 0 1 6 0" fill={color} />
        </G>
      );
    default:
      return null; // cycling -> raster overlay
  }
}

export function ProPin({ displayName, pinIcon, pinImageUrl }: ProPinProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const hasImage = !!pinImageUrl;
  const universe = !hasImage && pinIcon ? SPORT_CATEGORY_COLORS[pinIcon] : undefined;
  const ground = universe ? tint(universe) : colors.pinBackground;
  const glyph = universe ? glyphFor(pinIcon ?? '', universe) : null;
  const isBike = !!universe && pinIcon === 'cycling';
  const initial = (displayName.trim().charAt(0) || '?').toUpperCase();
  const cap = PIN_PRO_CAPSULE;

  return (
    <View style={styles.wrapper}>
      <Svg width={PIN_WIDTH} height={PIN_HEIGHT} viewBox={`${-PIN_PAD_X} ${-PIN_PAD_Y} ${VIEWBOX_W} ${VIEWBOX_H}`}>
        <PinBody fill={ground} outline={PRO_GOLD} path={PIN_SHIELD_PATH} edge={PIN_SHIELD_EDGE} />
        {hasImage && (
          <>
            <ClipPath id="proShieldClip"><Path d={PIN_SHIELD_PATH} /></ClipPath>
            <SvgImage
              href={{ uri: pinImageUrl }}
              x={IMAGE_BOX.x}
              y={IMAGE_BOX.y}
              width={IMAGE_BOX.w}
              height={IMAGE_BOX.h}
              preserveAspectRatio="xMidYMid slice"
              clipPath="url(#proShieldClip)"
            />
          </>
        )}
        {glyph && (
          <G transform={`translate(${GLYPH_CX} ${GLYPH_CY}) scale(${GLYPH_SCALE}) translate(-${PIN_HEAD_CX} -23)`}>{glyph}</G>
        )}
        {/* « PRO » capsule under the tip: gold, ink text — the pro badge of the pages. */}
        <Rect x={cap.x} y={cap.y} width={cap.w} height={cap.h} rx={cap.r} fill={PRO_GOLD} />
        <SvgText
          x={cap.x + cap.w / 2}
          y={cap.y + 9.1}
          fontSize={8}
          fontWeight="bold"
          letterSpacing={0.5}
          fill={PRO_GOLD_INK}
          textAnchor="middle"
        >
          PRO
        </SvgText>
      </Svg>
      {/* cycling = raster bike (universe tint); no icon, no image = the pro's initial */}
      {!hasImage && (isBike || !universe) && (
        <View style={styles.inner} pointerEvents="none">
          {isBike ? (
            <Image source={bikeGlyph} tintColor={universe} style={styles.bike} contentFit="contain" />
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
    // Centred on the glyph spot, in screen px.
    inner: {
      position: 'absolute',
      left: INNER_LEFT,
      top: INNER_TOP,
      width: INNER_D,
      height: INNER_D,
      alignItems: 'center',
      justifyContent: 'center',
    },
    bike: {
      width: INNER_D * 0.86,
      height: INNER_D * 0.56,
    },
    letter: {
      color: colors.pinBorder,
      fontSize: 15,
      fontWeight: '800',
      letterSpacing: -0.5,
    },
  });
