import { memo } from 'react';
import { SvgXml } from 'react-native-svg';
import { SPORT_ICON_XML } from '@/constants/sport-icon-svgs';
import { sportIconColor } from '@/constants/sport-universe';

interface SportIconProps {
  sportKey: string;
  size: number;
  /** Defaults to the sport's universe colour (T1). Pass ink for map pins,
      white on solid universe surfaces. */
  color?: string;
}

// The professional sport glyph that replaces the emoji set (validated
// per-sport mapping, 2026-09-11). `color` drives fill via currentColor:
// universe colour on T1 surfaces (cards/lists), fixed ink on map pins.
// Unknown key → renders nothing; callers keep their emoji fallback via
// hasSportIcon() where a visual is mandatory.
export const SportIcon = memo(function SportIcon({ sportKey, size, color }: SportIconProps) {
  const xml = SPORT_ICON_XML[sportKey];
  if (!xml) return null;
  return <SvgXml xml={xml} width={size} height={size} color={color ?? sportIconColor(sportKey, '#1F1A15')} />;
});
