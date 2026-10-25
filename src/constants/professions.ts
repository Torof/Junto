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
