import { isProProfession, PROFESSION_PICTO, PROFESSION_UNIVERSE } from '@/constants/professions';
import { PRO_PIN_ICONS } from '@/constants/pro-pin-icons';

// What the pro page pin shows (Scott 2026-10-26, four ways — DECISIONS « Pin
// de la page pro »): the pro's image fills the shield; else `pin_icon` names
// a universe (its glyph) or a sport (its picto) ; else the profession's
// picto ; else nothing but the initial. The universe only ever shows as the
// shield's pale tint. Shared by the pin, the map's cluster ring and labels.
export type ProPinLook =
  | { kind: 'image'; universe: null }
  | { kind: 'universe'; universe: string }
  | { kind: 'picto'; picto: string; universe: string | null }
  | { kind: 'initial'; universe: null };

const UNIVERSE_KEYS = new Set(PRO_PIN_ICONS.map((o) => o.key));

export function proPinLook(
  pro: { pin_image_url?: string | null; pin_icon?: string | null; profession?: string | null },
  sportCategoryOf: (sportKey: string) => string | null | undefined,
): ProPinLook {
  if (pro.pin_image_url) return { kind: 'image', universe: null };
  const icon = pro.pin_icon ?? null;
  if (icon && UNIVERSE_KEYS.has(icon)) return { kind: 'universe', universe: icon };
  if (icon) return { kind: 'picto', picto: icon, universe: sportCategoryOf(icon) ?? null };
  if (isProProfession(pro.profession)) {
    return { kind: 'picto', picto: PROFESSION_PICTO[pro.profession], universe: PROFESSION_UNIVERSE[pro.profession] };
  }
  return { kind: 'initial', universe: null };
}
