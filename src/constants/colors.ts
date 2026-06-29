export const darkColors = {
  background: '#0D1B2A',
  surface: '#1B3A5C',
  surfaceAlt: '#142D48',
  cta: '#F4642A',

  textPrimary: '#F5F5F0',
  textSecondary: '#8A9BB0',
  textMuted: '#5B6B85',

  success: '#2ECC71',
  error: '#E74C3C',
  warning: '#F39C12',

  pinStart: '#22c55e',
  pinMeeting: '#3b82f6',
  pinEnd: '#ef4444',
  pinObjective: '#F5A623',

  pinBackground: '#F5F5F0',
  pinBorder: '#0D1B2A',
  // Default UA frame — warm beige, visible against the ivory plate
  // without competing with the status colors (green/amber) that
  // replace it when the activity is soon / in progress. Deliberately
  // WARM: Mapbox geography tones are cool/desaturated, so a cool
  // stone (#DCD8D0, rejected on-device) blended into terrain while
  // warmth reads as a designed element.
  pinFrame: '#E0D2B4',
  // Pro family pins (PP storefront + RA offerings) — the SAME blue as
  // the pro tier badge on profiles (= pinMeeting), Scott's call
  // 2026-06-11: one color, one meaning ("pro") across surfaces, so the
  // map teaches itself. Water-collision risk is mitigated by the frame
  // grammar (slim blue frame + dark outline + ivory plate, not a blue
  // blob). History: orange (too urgent), navy + #4F46E5 (too dark),
  // #8B93F8 (right feel, wrong hue) all rejected on-device.
  // Same values in both themes: pins sit on the map, whose style is
  // user-chosen independently of the app theme.
  pinProBackground: '#3b82f6',
  pinProBorder: '#F5F5F0',
  // PP pushpin (v4): grey head rim on the white Google-place body. Same in
  // both themes — the pin sits on the (independently-styled) map.
  pinProRim: '#6B7280',
  border: 'transparent',
  line: 'rgba(255,255,255,0.08)',
  // 2× alpha of `line` — for elements that need a clearly contained
  // border (e.g. card-pills nested inside a card body) where the
  // standard `line` reads too quietly.
  lineStrong: 'rgba(255,255,255,0.18)',
  // Brutalist 1px-solid border (near-opposite of bg). Use on cards,
  // notif rows, inputs and other surfaces that should read as
  // sharply-defined containers, not floating soft shapes.
  borderStrong: '#F5F5F0',
  borderMuted: 'rgba(255,255,255,0.34)',
  overlay: 'rgba(0,0,0,0.65)',
};

// Warmed 2026-06-11 (light is now the default theme): shifted from a
// cool grey-white off-white toward the website's warm cream family —
// the cool palette read "clinical / too bright / harsh". Warming the
// canvas + greys calms perceived saturation and unifies app ↔ web.
// Pins, semantic colors (success/error/warning) and CTA hue left as the
// validated tokens; only the canvas, surfaces and neutral greys warm.
export const lightColors = {
  background: '#F5EEDF',
  surface: '#EDE4D2',
  surfaceAlt: '#E3D9C4',
  cta: '#F26B2E',

  textPrimary: '#1F1A15',
  textSecondary: '#6F665A',
  textMuted: '#A0968A',

  success: '#2ECC71',
  error: '#E74C3C',
  warning: '#F39C12',

  pinStart: '#22c55e',
  pinMeeting: '#3b82f6',
  pinEnd: '#ef4444',
  pinObjective: '#F5A623',

  pinBackground: '#FFFFFF',
  pinBorder: '#1F1A15',
  pinFrame: '#E0D2B4',
  pinProBackground: '#3b82f6',
  pinProBorder: '#F5F5F0',
  // PP pushpin (v4): grey head rim on the white Google-place body. Same in
  // both themes — the pin sits on the (independently-styled) map.
  pinProRim: '#6B7280',
  border: '#B3AC9C',
  line: 'rgba(31,26,21,0.08)',
  lineStrong: 'rgba(31,26,21,0.16)',
  // Brutalist 1px-solid border (near-opposite of bg).
  borderStrong: '#1F1A15',
  borderMuted: 'rgba(31,26,21,0.34)',
  overlay: 'rgba(0,0,0,0.5)',
};

export type AppColors = typeof darkColors;

// Static fallback for files not yet migrated to useColors()
export const colors = darkColors;
