// Map pin grammar, chosen on device by Scott 2026-10-16 (mockup
// https://claude.ai/artifact/HDGWhWQr1fcA7um8FSJnVs, style « B » over the
// historical lemon-body / ivory-plate / ink-outline pin):
//   - soft SVG-drawn shadow, rounded tip (2026-10-23: + white outline, two-layer shadow);
//   - outing: body = universe colour, white glyph; the status colour takes
//     the body when the outing is soon / in progress;
//   - pro outing: the same shape in pro blue, white « PRO » capsule;
//   - pro page: the same shape in white with the universe disc inside —
//     white = « a place », colour = « an outing ».

// Rounded-tip silhouette shared by activity / offering / pro pins, drawn
// in the historical 54-wide design space (head centre (27, 23), tip (27, 51.6)).
export const PIN_DROP_PATH =
  'M 27 3 C 15.4 3 6 12.2 6 23.5 C 6 33.5 18.5 43.5 24.6 50.2 C 25.9 51.6 28.1 51.6 29.4 50.2 C 35.5 43.5 48 33.5 48 23.5 C 48 12.2 38.6 3 27 3 Z';
export const PIN_DROP_TIP_Y = 51.6;
export const PIN_HEAD_CX = 27;
export const PIN_HEAD_CY = 23;

// 2026-10-23 (mockup board « Contraste », choice A + B shadow): the pin
// blended into the ground — a green pin on Outdoors forest, a dark one on
// satellite. A white outline (≈1.5 px on screen at the 40-px pin) now
// detaches it from any ground, and a two-layer shadow sets it on the map.
// Drawn by components/pin-body.tsx for every pin.
export const PIN_OUTLINE = { color: '#FFFFFF', width: 4 } as const; // design units (54-wide drop): 2 outside
export const PIN_SHADOW_NEAR = { dx: 0, dy: 2, blur: 1.2, color: '#0A0F1A', opacity: 0.45 } as const;
export const PIN_SHADOW_FAR = { dx: 0, dy: 5, blur: 4, color: '#0A0F1A', opacity: 0.3 } as const;

// Room left around the shape inside the SVG so the outline and the wide
// shadow are not clipped (an SVG clips to its bounds; a transparent RN View
// casts no shadow on Android).
export const PIN_PAD_X = 12;
export const PIN_PAD_Y = 14;
