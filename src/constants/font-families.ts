import type { TextStyle } from 'react-native';
import { Outfit_400Regular } from '@expo-google-fonts/outfit/400Regular';
import { Outfit_500Medium } from '@expo-google-fonts/outfit/500Medium';
import { Outfit_600SemiBold } from '@expo-google-fonts/outfit/600SemiBold';
import { Outfit_700Bold } from '@expo-google-fonts/outfit/700Bold';
import { Outfit_800ExtraBold } from '@expo-google-fonts/outfit/800ExtraBold';
import { PlusJakartaSans_400Regular } from '@expo-google-fonts/plus-jakarta-sans/400Regular';
import { PlusJakartaSans_500Medium } from '@expo-google-fonts/plus-jakarta-sans/500Medium';
import { PlusJakartaSans_600SemiBold } from '@expo-google-fonts/plus-jakarta-sans/600SemiBold';
import { PlusJakartaSans_700Bold } from '@expo-google-fonts/plus-jakarta-sans/700Bold';
import { PlusJakartaSans_800ExtraBold } from '@expo-google-fonts/plus-jakarta-sans/800ExtraBold';
import { Manrope_400Regular } from '@expo-google-fonts/manrope/400Regular';
import { Manrope_500Medium } from '@expo-google-fonts/manrope/500Medium';
import { Manrope_600SemiBold } from '@expo-google-fonts/manrope/600SemiBold';
import { Manrope_700Bold } from '@expo-google-fonts/manrope/700Bold';
import { Manrope_800ExtraBold } from '@expo-google-fonts/manrope/800ExtraBold';
import { Inter_400Regular } from '@expo-google-fonts/inter/400Regular';
import { Inter_500Medium } from '@expo-google-fonts/inter/500Medium';
import { Inter_600SemiBold } from '@expo-google-fonts/inter/600SemiBold';
import { Inter_700Bold } from '@expo-google-fonts/inter/700Bold';
import { Inter_800ExtraBold } from '@expo-google-fonts/inter/800ExtraBold';
import { DMSans_400Regular } from '@expo-google-fonts/dm-sans/400Regular';
import { DMSans_500Medium } from '@expo-google-fonts/dm-sans/500Medium';
import { DMSans_600SemiBold } from '@expo-google-fonts/dm-sans/600SemiBold';
import { DMSans_700Bold } from '@expo-google-fonts/dm-sans/700Bold';
import { DMSans_800ExtraBold } from '@expo-google-fonts/dm-sans/800ExtraBold';
import { Archivo_400Regular } from '@expo-google-fonts/archivo/400Regular';
import { Archivo_500Medium } from '@expo-google-fonts/archivo/500Medium';
import { Archivo_600SemiBold } from '@expo-google-fonts/archivo/600SemiBold';
import { Archivo_700Bold } from '@expo-google-fonts/archivo/700Bold';
import { Archivo_800ExtraBold } from '@expo-google-fonts/archivo/800ExtraBold';
import { fonts } from './typography';

// User-selectable font families (Scott 2026-10-23, Settings → Personnalisation).
//
// The rule that makes a family swappable without breaking a single layout:
// every family is normalised to the WIDTH of Roboto (the Android system font
// the whole UI was designed and tested in). `scale` is Roboto's advance width
// divided by the family's, measured per weight on a sample of real French UI
// strings (scratch tool fontwidth.py) — a line that fits in Roboto fits in any
// family. To add a family: its five weight files + its measured scales here.
//
// Android needs one family NAME per weight file (fontWeight alone does not pick
// a loaded file), hence `files` keyed by weight; <AppText> maps the style's
// fontWeight onto the right name and drops fontWeight.

export type FontWeightKey = '400' | '500' | '600' | '700' | '800';
export const FONT_WEIGHTS: readonly FontWeightKey[] = ['400', '500', '600', '700', '800'];

export type FontFamilyId = 'system' | 'outfit' | 'plus-jakarta-sans' | 'manrope' | 'inter' | 'dm-sans' | 'archivo';

interface CustomFamily {
  label: string;
  files: Record<FontWeightKey, number>;
  scale: Record<FontWeightKey, number>;
}

const CUSTOM: Record<Exclude<FontFamilyId, 'system'>, CustomFamily> = {
  outfit: {
    label: 'Outfit',
    files: { '400': Outfit_400Regular, '500': Outfit_500Medium, '600': Outfit_600SemiBold, '700': Outfit_700Bold, '800': Outfit_800ExtraBold },
    scale: { '400': 1.018, '500': 1.026, '600': 1.013, '700': 1.001, '800': 0.99 },
  },
  'plus-jakarta-sans': {
    label: 'Plus Jakarta Sans',
    files: { '400': PlusJakartaSans_400Regular, '500': PlusJakartaSans_500Medium, '600': PlusJakartaSans_600SemiBold, '700': PlusJakartaSans_700Bold, '800': PlusJakartaSans_800ExtraBold },
    scale: { '400': 0.963, '500': 0.961, '600': 0.956, '700': 0.95, '800': 0.945 },
  },
  manrope: {
    label: 'Manrope',
    files: { '400': Manrope_400Regular, '500': Manrope_500Medium, '600': Manrope_600SemiBold, '700': Manrope_700Bold, '800': Manrope_800ExtraBold },
    scale: { '400': 0.981, '500': 0.973, '600': 0.96, '700': 0.948, '800': 0.936 },
  },
  inter: {
    label: 'Inter',
    files: { '400': Inter_400Regular, '500': Inter_500Medium, '600': Inter_600SemiBold, '700': Inter_700Bold, '800': Inter_800ExtraBold },
    scale: { '400': 0.937, '500': 0.937, '600': 0.933, '700': 0.928, '800': 0.923 },
  },
  'dm-sans': {
    label: 'DM Sans',
    files: { '400': DMSans_400Regular, '500': DMSans_500Medium, '600': DMSans_600SemiBold, '700': DMSans_700Bold, '800': DMSans_800ExtraBold },
    scale: { '400': 0.962, '500': 0.955, '600': 0.941, '700': 0.93, '800': 0.93 },
  },
  archivo: {
    label: 'Archivo',
    files: { '400': Archivo_400Regular, '500': Archivo_500Medium, '600': Archivo_600SemiBold, '700': Archivo_700Bold, '800': Archivo_800ExtraBold },
    scale: { '400': 1.011, '500': 1.004, '600': 0.99, '700': 0.962, '800': 0.923 },
  },
};

// Picker order; 'system' last.
export const FONT_FAMILY_IDS: readonly FontFamilyId[] = ['outfit', 'plus-jakarta-sans', 'manrope', 'inter', 'dm-sans', 'archivo', 'system'];
export const DEFAULT_FONT_FAMILY: FontFamilyId = 'system';

export function isFontFamilyId(v: unknown): v is FontFamilyId {
  return typeof v === 'string' && (FONT_FAMILY_IDS as readonly string[]).includes(v);
}

export function fontFamilyLabel(id: Exclude<FontFamilyId, 'system'>): string {
  return CUSTOM[id].label;
}

// Registered name of one weight file, e.g. 'outfit-700'.
export function fontFileName(id: Exclude<FontFamilyId, 'system'>, weight: FontWeightKey): string {
  return `${id}-${weight}`;
}

// The map expo-font's loadAsync takes, for the given weights of a family.
export function fontFileMap(id: Exclude<FontFamilyId, 'system'>, weights: readonly FontWeightKey[] = FONT_WEIGHTS): Record<string, number> {
  const out: Record<string, number> = {};
  for (const w of weights) out[fontFileName(id, w)] = CUSTOM[id].files[w];
  return out;
}

// Style values → one of the five loaded weights. Canon weights are numeric
// strings; 'bold'/'normal' and the extremes snap to the nearest file.
function weightKey(w: TextStyle['fontWeight'] | undefined): FontWeightKey | undefined {
  if (w === undefined) return undefined;
  if (w === 'bold') return '700';
  if (w === 'normal') return '400';
  const n = Number(w);
  if (!Number.isFinite(n)) return '400';
  if (n <= 400) return '400';
  if (n >= 800) return '800';
  return String(Math.round(n / 100) * 100) as FontWeightKey;
}

const RN_DEFAULT_FONT_SIZE = 14;

// What a nested <AppText> inherits from its parent: React Native passes
// fontWeight/fontSize down to nested Text, but once those become a family
// name and a scaled size the child must recompute them from the parent's
// UNSCALED values, or a bare nested span would reset to 400 / 14.
export interface InheritedFont {
  weight: FontWeightKey;
  size: number;
}

export function resolveTextStyle(
  family: FontFamilyId,
  style: TextStyle | undefined,
  parent: InheritedFont | null,
): { style: TextStyle | undefined; inherited: InheritedFont | null } {
  const own = style ?? {};
  const fam = own.fontFamily;
  // A deliberate non-token family (e.g. 'monospace' for ids) is left alone.
  if (fam !== undefined && fam !== fonts.title && fam !== fonts.body) return { style, inherited: parent };

  const weight = weightKey(own.fontWeight) ?? (fam === fonts.title ? '800' : parent?.weight ?? '400');
  const size = own.fontSize ?? parent?.size ?? RN_DEFAULT_FONT_SIZE;
  const inherited = { weight, size };
  const { fontFamily: _f, fontWeight: _w, ...rest } = own;

  if (family === 'system') {
    return { style: { ...rest, fontWeight: weight }, inherited };
  }
  return {
    style: { ...rest, fontFamily: fontFileName(family, weight), fontSize: Math.round(size * CUSTOM[family].scale[weight] * 100) / 100 },
    inherited,
  };
}
