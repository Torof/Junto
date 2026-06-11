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
  // Pro family pins (PP storefront + RA offerings) — light indigo
  // frame, light outline. Indigo is the one calm-catchy hue nothing
  // on an outdoor map owns (green/amber = statuses, blue = water,
  // orange = too urgent). Navy and saturated indigo #4F46E5 both
  // rejected on-device 2026-06-11 as too dark/heavy next to the
  // ivory peer pins.
  // Same values in both themes: pins sit on the map, whose style is
  // user-chosen independently of the app theme.
  pinProBackground: '#8B93F8',
  pinProBorder: '#F5F5F0',
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
  borderMuted: 'rgba(255,255,255,0.18)',
  overlay: 'rgba(0,0,0,0.65)',
};

export const lightColors = {
  background: '#F5F5F0',
  surface: '#E0DDD8',
  surfaceAlt: '#D4D0CB',
  cta: '#F4642A',

  textPrimary: '#1A1A1A',
  textSecondary: '#6B7280',
  textMuted: '#9CA3AF',

  success: '#2ECC71',
  error: '#E74C3C',
  warning: '#F39C12',

  pinStart: '#22c55e',
  pinMeeting: '#3b82f6',
  pinEnd: '#ef4444',
  pinObjective: '#F5A623',

  pinBackground: '#FFFFFF',
  pinBorder: '#1A1A1A',
  pinFrame: '#E0D2B4',
  pinProBackground: '#8B93F8',
  pinProBorder: '#F5F5F0',
  border: '#9E9A95',
  line: 'rgba(0,0,0,0.08)',
  lineStrong: 'rgba(0,0,0,0.18)',
  // Brutalist 1px-solid border (near-opposite of bg).
  borderStrong: '#1A1A1A',
  borderMuted: 'rgba(0,0,0,0.18)',
  overlay: 'rgba(0,0,0,0.5)',
};

export type AppColors = typeof darkColors;

// Static fallback for files not yet migrated to useColors()
export const colors = darkColors;
