import { useMemo, type ReactNode } from 'react';
import { View, StyleSheet } from 'react-native';
import { AppText } from '@/components/app-text';
import Svg, { Path, G, Rect, Text as SvgText, ClipPath, Image as SvgImage, SvgXml } from 'react-native-svg';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { useSports } from '@/hooks/use-sports';
import { SPORT_CATEGORY_COLORS } from '@/utils/sport-category-color';
import { SPORT_ICON_XML } from '@/constants/sport-icon-svgs';
import { PRO_PICTO_XML } from '@/constants/pro-pictos';
import { proPinLook } from '@/utils/pro-pin-look';
import {
  PIN_DROP_TIP_Y, PIN_HEAD_CX, PIN_PAD_X, PIN_PAD_Y, PIN_PRO_CAPSULE, PIN_SHIELD_EDGE, PIN_SHIELD_PATH,
  PRO_GOLD, PRO_GOLD_INK,
} from '@/constants/pin-style';
import { PinBody } from '@/components/pin-body';

interface ProPinProps {
  displayName: string;
  pinIcon?: string | null;
  profession?: string | null;
  // Optional custom image — fills the WHOLE shield (clipped to it); the
  // silhouette never changes, so the map stays coherent whatever the image.
  pinImageUrl?: string | null;
}

// The pro PAGE pin (Scott 2026-10-26, mockups « E3 », « U4 », « F », « Les
// treize métiers »): a SHIELD — « someone », where every outing is a drop —
// with the gold outline and a thin ink edge outside it, and the gold PRO
// capsule hanging under the tip. Four ways to fill it (utils/pro-pin-look):
// the pro's image ; a universe glyph ; a sport picto of the 38-set ; the
// profession's picto (default). Glyph and picto are INK on a pale tint of
// the universe (30 %): pale = a person, full colour = an outing.
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
const PICTO_PX = Math.round(24 * SCALE);
// The image box = the shield's bounding box; `slice` crops it to the shield.
const IMAGE_BOX = { x: 7, y: 3, w: 40, h: 49 };
const TINT_ALPHA = 0.3; // 20 % read too pale on device (Scott 2026-10-26)

// Universes whose glyph is a picto of the sets rather than a path here.
const UNIVERSE_PICTO: Record<string, string> = { cycling: 'cycling', wellness: 'lotus' };

export const PRO_PIN_ANCHOR = {
  x: 0.5,
  y: (PIN_DROP_TIP_Y + PIN_PAD_Y) / VIEWBOX_H,
};

// The universe colour at `alpha` over white — the shield's ground.
function tint(hex: string, alpha: number): string {
  const n = parseInt(hex.slice(1), 16);
  const mix = (c: number) => Math.round(255 + (c - 255) * alpha).toString(16).padStart(2, '0');
  return `#${mix((n >> 16) & 255)}${mix((n >> 8) & 255)}${mix(n & 255)}`;
}

// Universe glyphs (Scott 2026-10-26, planche « glyphes d'univers ») drawn in a
// 24-box centred on the head and scaled around (27, 23), in ink. Cycling and
// wellness are pictos (the set's `cycling`, the lotus) — see UNIVERSE_PICTO.
function glyphFor(key: string, color: string): ReactNode {
  switch (key) {
    case 'mountain':
      // Two peaks, flat (Scott 2026-10-26: snow caps did not read on the pale tint).
      return (
        <G transform="translate(15 12)">
          <Path d="M2 20 L8.5 7 L12.2 13.5 L15 9 L22 20 Z" fill={color} />
        </G>
      );
    case 'water':
      // The drop, with a light reflection (planche « glyphes », Eau B).
      return (
        <G transform="translate(15 12)">
          <Path d="M12 2 C 12 2 5 10.2 5 14.5 A 7 7 0 0 0 19 14.5 C 19 10.2 12 2 12 2 Z" fill={color} />
          <Path d="M8.2 14.8 C 8.2 12.6 9.3 10.8 10.4 9.5 L 9.2 8.6 C 7.9 10.1 7 12.3 7 14.8 Z" fill="#FFFFFF" opacity={0.55} />
        </G>
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
    default:
      return null; // cycling → the set's bike, wellness → the lotus (pictos)
  }
}

export function ProPin({ displayName, pinIcon, profession, pinImageUrl }: ProPinProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { data: sports } = useSports();
  const categoryOf = useMemo(() => {
    const m = new Map((sports ?? []).map((s) => [s.key, s.category]));
    return (key: string) => m.get(key);
  }, [sports]);

  const look = proPinLook({ pin_image_url: pinImageUrl, pin_icon: pinIcon, profession }, categoryOf);
  const universeColor = look.universe ? SPORT_CATEGORY_COLORS[look.universe] : undefined;
  const ground = universeColor ? tint(universeColor, TINT_ALPHA) : colors.pinBackground;
  const ink = colors.pinBorder;
  const glyph = look.kind === 'universe' ? glyphFor(look.universe, ink) : null;
  const pictoKey = look.kind === 'picto' ? look.picto : look.kind === 'universe' ? UNIVERSE_PICTO[look.universe] : undefined;
  const pictoXml = pictoKey ? (SPORT_ICON_XML[pictoKey] ?? PRO_PICTO_XML[pictoKey]) : undefined;
  const initial = (displayName.trim().charAt(0) || '?').toUpperCase();
  const cap = PIN_PRO_CAPSULE;

  return (
    <View style={styles.wrapper}>
      <Svg width={PIN_WIDTH} height={PIN_HEIGHT} viewBox={`${-PIN_PAD_X} ${-PIN_PAD_Y} ${VIEWBOX_W} ${VIEWBOX_H}`}>
        <PinBody fill={ground} outline={PRO_GOLD} path={PIN_SHIELD_PATH} edge={PIN_SHIELD_EDGE} />
        {look.kind === 'image' && (
          <>
            <ClipPath id="proShieldClip"><Path d={PIN_SHIELD_PATH} /></ClipPath>
            <SvgImage
              href={{ uri: pinImageUrl ?? undefined }}
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
      {/* picto (sport, profession, cycling or wellness universe) · nothing = the pro's initial */}
      {(pictoXml || look.kind === 'initial') && (
        <View style={styles.inner} pointerEvents="none">
          {pictoXml ? (
            <SvgXml xml={pictoXml} width={PICTO_PX} height={PICTO_PX} color={ink} />
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
    letter: {
      color: colors.pinBorder,
      fontSize: 15,
      fontWeight: '800',
      letterSpacing: -0.5,
    },
  });
