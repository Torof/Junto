import { Platform } from 'react-native';

// Depth tokens — the missing contrast cue on the warm cream surfaces (Scott,
// 2026-07-04). Warm near-black, soft and low: cards should float a hair above
// the canvas, not hover. Spread into a style object; the view needs a solid
// backgroundColor for Android elevation to render.
export const shadows = {
  // Content cards on a drawer/page canvas.
  card: Platform.select({
    ios: {
      shadowColor: '#1F1A15',
      shadowOffset: { width: 0, height: 2 },
      shadowOpacity: 0.1,
      shadowRadius: 5,
    },
    default: { elevation: 2, shadowColor: '#1F1A15' },
  }),
  // Hero cards that should clearly pop (catalogue experience cards).
  raised: Platform.select({
    ios: {
      shadowColor: '#1F1A15',
      shadowOffset: { width: 0, height: 3 },
      shadowOpacity: 0.16,
      shadowRadius: 8,
    },
    default: { elevation: 4, shadowColor: '#1F1A15' },
  }),
  // Drawer/sheet shells floating over the map — must be visible at the TOP
  // edge, so iOS casts upward (negative offset) and Android gets a heavy
  // elevation (its ambient halo is what reads above the view).
  sheet: Platform.select({
    ios: {
      shadowColor: '#1F1A15',
      shadowOffset: { width: 0, height: -6 },
      shadowOpacity: 0.22,
      shadowRadius: 14,
    },
    default: { elevation: 16, shadowColor: '#1F1A15' },
  }),
} as const;
