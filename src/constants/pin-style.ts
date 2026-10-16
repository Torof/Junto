// Map pin grammar, chosen on device by Scott 2026-10-16 (mockup
// https://claude.ai/artifact/HDGWhWQr1fcA7um8FSJnVs, style « B » over the
// historical lemon-body / ivory-plate / ink-outline pin):
//   - no outline, soft SVG-drawn shadow, rounded tip;
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

// Room left around the shape inside the SVG so the shadow is not clipped
// (an SVG clips to its bounds; a transparent RN View casts no shadow on Android).
export const PIN_PAD_X = 10;
export const PIN_PAD_Y = 8;
// Drop shadow — one soft layer, slightly below the shape.
export const PIN_SHADOW = { dx: 0, dy: 3, blur: 2.4, color: '#0A0F1A', opacity: 0.38 } as const;
