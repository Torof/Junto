// The app's exact pin system, as web SVGs — single source for the hero and
// the section map banners. Geometry copied verbatim from the app components
// (activity-pin.tsx / pro-offering-pin.tsx / pro-pin.tsx).

export const INK = '#1F1A15';
export const STONE = '#E0D2B4';
export const PRO_FRAME = '#BFCFE0';
export const PRO_BLUE = '#3b82f6';

export const TEARDROP =
  'M 27 2 C 13 2 4 12 4 25 C 4 36 21 50 27 52 C 33 50 50 36 50 25 C 50 12 41 2 27 2 Z';

// UA — stone teardrop, ivory plate, sport emoji.
export function UaPin({ emoji }: { emoji: string }) {
  return (
    <>
      <svg width="44" height="44" viewBox="0 0 54 54">
        <path d={TEARDROP} fill={STONE} stroke={INK} strokeWidth="2" strokeOpacity=".55" strokeLinejoin="round" />
        <circle cx="27" cy="24" r="18.5" fill="#FFFFFF" stroke={INK} strokeWidth="1.5" strokeOpacity=".95" />
      </svg>
      <span className="junto-hero-pin-emoji">{emoji}</span>
    </>
  );
}

// RA — blue-grey frame + the PRO capsule top-left.
export function RaPin({ emoji }: { emoji: string }) {
  return (
    <>
      <svg width="48" height="45" viewBox="0 0 58 54">
        <g transform="translate(4 0)">
          <path d={TEARDROP} fill={PRO_FRAME} stroke={INK} strokeWidth="2" strokeOpacity=".55" strokeLinejoin="round" />
          <circle cx="27" cy="24" r="18.5" fill="#FFFFFF" stroke={INK} strokeWidth="1.5" strokeOpacity=".95" />
        </g>
        <rect x="1" y="1.5" width="22" height="12" rx="6" fill={PRO_BLUE} stroke={INK} strokeWidth="1.3" />
        <text x="12" y="10.6" fontSize="8" fontWeight="bold" letterSpacing=".5" fill="#FFFFFF" textAnchor="middle" fontFamily="system-ui, sans-serif">
          PRO
        </text>
      </svg>
      <span className="junto-hero-pin-emoji" style={{ left: 4 }}>{emoji}</span>
    </>
  );
}

// PP — pushpin: white head, grey rim, universe disc + white glyph.
export function PpPin() {
  return (
    <svg width="40" height="52" viewBox="0 0 54 70">
      <path d="M 24.6 41 L 27 67 L 29.4 41 Z" fill={INK} />
      <circle cx="27" cy="23" r="21" fill="#FFFFFF" stroke="#6B7280" strokeWidth="1.3" />
      <circle cx="27" cy="23" r="18.5" fill="#4A7C59" />
      <g transform="translate(27 23) scale(0.8) translate(-27 -23)">
        <path d="M 15 32 L 23 16 L 28 23 L 32 18 L 39 32 Z" fill="#F5F5F0" />
      </g>
    </svg>
  );
}
