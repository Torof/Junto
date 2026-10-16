// Map pin style under on-device comparison (Scott 2026-10-16, mockup
// https://claude.ai/artifact/HDGWhWQr1fcA7um8FSJnVs). Both drop the ink
// outline and the sharp drop tip for a soft SVG-drawn shadow and a rounded
// tip; they differ in what fills the body:
//   'A' — the current grammar kept: body = status colour (lemon by default),
//         ivory plate, glyph in the universe colour; pros keep a softened
//         pushpin (no rim, short rounded needle).
//   'B' — Meta-style: body = universe colour (status colour takes the body
//         when the outing is soon / in progress), white glyph; pros take the
//         same rounded shape in white with a universe disc.
// Flip, OTA, compare on the real map; the loser gets deleted.
export const PIN_STYLE: 'A' | 'B' = 'A';

// Rounded-tip silhouette shared by activity / offering / (B) pro pins, drawn
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
