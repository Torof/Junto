// The pro's declared profession (00554): a closed list, codes stable in the
// database, labels in the app (`pro.profession.<code>`, five languages).
// Shown under the name on the pro page; the map filters pros by it.
// Order = the order of the picker (mountain → water → air → the rest).
export const PRO_PROFESSIONS = [
  'mountain_guide',
  'mountain_leader',
  'climbing_instructor',
  'canyoning_instructor',
  'whitewater_instructor',
  'diving_instructor',
  'surf_instructor',
  'paragliding_instructor',
  'ski_instructor',
  'mtb_instructor',
  'wellness_instructor',
  'school_office',
  'other',
] as const;

export type ProProfession = (typeof PRO_PROFESSIONS)[number];

export function isProProfession(value: string | null | undefined): value is ProProfession {
  return !!value && (PRO_PROFESSIONS as readonly string[]).includes(value);
}

// The profession's universe — the pale tint of the pro shield when the pro
// shows their profession (pin_icon NULL, 00557). null = white shield.
export const PROFESSION_UNIVERSE: Record<ProProfession, string | null> = {
  mountain_guide: 'mountain',
  mountain_leader: 'mountain',
  climbing_instructor: 'mountain',
  canyoning_instructor: 'water',
  whitewater_instructor: 'water',
  diving_instructor: 'water',
  surf_instructor: 'water',
  paragliding_instructor: 'air',
  ski_instructor: 'mountain',
  mtb_instructor: 'cycling',
  wellness_instructor: 'wellness',
  school_office: null,
  other: null,
};

// The profession's picto on the shield (Scott 2026-10-26, planche « Les
// treize métiers ») — a sport key of the 38-set where one sport sums up the
// profession (the same drawing as that sport's outings), else a key of
// PRO_PICTO_XML (constants/pro-pictos.ts).
export const PROFESSION_PICTO: Record<ProProfession, string> = {
  mountain_guide: 'mountaineering',
  mountain_leader: 'hiking',
  climbing_instructor: 'climbing-sport',
  canyoning_instructor: 'canyoning',
  whitewater_instructor: 'kayaking',
  diving_instructor: 'diving',
  surf_instructor: 'surfing',
  paragliding_instructor: 'paragliding',
  ski_instructor: 'skiing',
  mtb_instructor: 'mtb-xc',
  wellness_instructor: 'lotus',
  school_office: 'school',
  other: 'briefcase',
};
