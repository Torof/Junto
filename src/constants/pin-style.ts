// Map pin grammar, chosen on device by Scott 2026-10-16 (mockup
// https://claude.ai/artifact/HDGWhWQr1fcA7um8FSJnVs, style « B » over the
// historical lemon-body / ivory-plate / ink-outline pin):
//   - soft SVG-drawn shadow, rounded tip (2026-10-23: + white outline, two-layer shadow);
//   - outing: body = universe colour, white glyph; the status colour takes
//     the body when the outing is soon / in progress;
//   - pro outing: the same shape in pro blue, « PRO » capsule;
//   - pro page: 2026-10-26 a SHIELD (PIN_SHIELD_PATH) — gold outline, thin
//     ink edge, PRO capsule under the tip; the pro's pin image fills it, or
//     a pale tint of the universe with the universe glyph in full colour
//     (« someone », pale, vs « an outing », full colour);
//   - 2026-10-25 (DECISIONS « Couleur pro : l'or ») : the two pro pins keep
//     their body and take a GOLD outline instead of the white one; the PRO
//     capsule is gold with ink text — the same badge as the pro pages.

// Rounded-tip silhouette shared by activity / offering / pro pins, drawn
// in the historical 54-wide design space (head centre (27, 23), tip (27, 51.6)).
export const PIN_DROP_PATH =
  'M 27 3 C 15.4 3 6 12.2 6 23.5 C 6 33.5 18.5 43.5 24.6 50.2 C 25.9 51.6 28.1 51.6 29.4 50.2 C 35.5 43.5 48 33.5 48 23.5 C 48 12.2 38.6 3 27 3 Z';
export const PIN_DROP_TIP_Y = 51.6;
// The pro PAGE pin's shield (Scott 2026-10-26, mockup « E3 » then « U4 »):
// same 54-wide space, same tip as the drop, shoulders at y 7.5. Outside the
// gold outline it carries a thin ink edge; the PRO capsule hangs under the tip.
export const PIN_SHIELD_PATH =
  'M 27 3 C 34 6 41 7.5 47 7.5 C 47 22 44 36 29.6 50.2 C 28.2 51.6 25.8 51.6 24.4 50.2 C 10 36 7 22 7 7.5 C 13 7.5 20 6 27 3 Z';
export const PIN_SHIELD_EDGE = { color: '#1F1A15', width: 6 } as const; // design units: 1 outside the gold
export const PIN_PRO_CAPSULE = { x: 16, y: 50.5, w: 22, h: 12, r: 6 } as const;
export const PIN_HEAD_CX = 27;
export const PIN_HEAD_CY = 23;

// 2026-10-23 (mockup board « Contraste », choice A + B shadow): the pin
// blended into the ground — a green pin on Outdoors forest, a dark one on
// satellite. A white outline (≈1.5 px on screen at the 40-px pin) now
// detaches it from any ground, and a two-layer shadow sets it on the map.
// Drawn by components/pin-body.tsx for every pin.
export const PIN_OUTLINE = { color: '#FFFFFF', width: 4 } as const; // design units (54-wide drop): 2 outside
// The pro colour — pin outline, PRO capsule, page badges, navbar dot. Nothing
// else in the app is gold, no sport universe is: it reads « pro » at once.
export const PRO_GOLD = '#F2B705';
export const PRO_GOLD_INK = '#1F1A15';
export const PIN_SHADOW_NEAR = { dx: 0, dy: 2, blur: 1.2, color: '#0A0F1A', opacity: 0.45 } as const;
export const PIN_SHADOW_FAR = { dx: 0, dy: 5, blur: 4, color: '#0A0F1A', opacity: 0.3 } as const;

// Room left around the shape inside the SVG so the outline and the wide
// shadow are not clipped (an SVG clips to its bounds; a transparent RN View
// casts no shadow on Android).
export const PIN_PAD_X = 12;
export const PIN_PAD_Y = 14;
