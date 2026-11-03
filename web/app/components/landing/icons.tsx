import type { SVGProps } from 'react';

type IconProps = SVGProps<SVGSVGElement> & { size?: number; color?: string; width2?: number };

function base({ size = 16, color = 'currentColor', width2 = 2.4, ...rest }: IconProps) {
  return {
    width: size,
    height: size,
    viewBox: '0 0 24 24',
    fill: 'none',
    stroke: color,
    strokeWidth: width2,
    strokeLinecap: 'round' as const,
    strokeLinejoin: 'round' as const,
    'aria-hidden': true,
    ...rest,
  };
}

export const IconPin = (p: IconProps) => (
  <svg {...base(p)}><path d="M12 21s-6-5.3-6-10a6 6 0 0 1 12 0c0 4.7-6 10-6 10z" /><circle cx="12" cy="11" r="2" /></svg>
);
export const IconCalendar = (p: IconProps) => (
  <svg {...base(p)}><rect x="3" y="4" width="18" height="18" rx="2" /><path d="M16 2v4M8 2v4M3 10h18" /></svg>
);
export const IconUsers = (p: IconProps) => (
  <svg {...base(p)}><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" /><circle cx="9" cy="7" r="4" /><path d="M22 21v-2a4 4 0 0 0-3-3.9M16 3.1a4 4 0 0 1 0 7.8" /></svg>
);
export const IconSearch = (p: IconProps) => (
  <svg {...base(p)}><circle cx="11" cy="11" r="7" /><path d="M20 20l-3.5-3.5" /></svg>
);
export const IconPlus = (p: IconProps) => (
  <svg {...base(p)}><path d="M12 5v14M5 12h14" /></svg>
);
export const IconMountain = (p: IconProps) => (
  <svg {...base(p)}><path d="M4 19l5-14 4 8 3-5 4 11" /></svg>
);
export const IconChevron = (p: IconProps) => (
  <svg {...base(p)}><path d="M6 9l6 6 6-6" /></svg>
);
export const IconClock = (p: IconProps) => (
  <svg {...base(p)}><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></svg>
);
export const IconCar = (p: IconProps) => (
  <svg {...base(p)}><path d="M5 17h14l-1.5-6h-11z" /><path d="M7 11l1.5-4h7L17 11" /><circle cx="7.5" cy="17.5" r="1.5" /><circle cx="16.5" cy="17.5" r="1.5" /></svg>
);
export const IconBackpack = (p: IconProps) => (
  <svg {...base(p)}><path d="M7 8a5 5 0 0 1 10 0v1h1a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-8a2 2 0 0 1 2-2h1z" /><path d="M9 9V8a3 3 0 0 1 6 0v1M8 15h8" /></svg>
);
export const IconChat = (p: IconProps) => (
  <svg {...base(p)}><path d="M21 12a8 8 0 0 1-8 8H6l-3 3V12a8 8 0 0 1 8-8h2a8 8 0 0 1 8 8z" /></svg>
);
export const IconHash = (p: IconProps) => (
  <svg {...base(p)}><path d="M4 9h16M4 15h16M10 3L8 21M16 3l-2 18" /></svg>
);

export const IconPhone = (p: IconProps) => (
  <svg {...base(p)}><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z" /></svg>
);
export const IconNavigation = (p: IconProps) => (
  <svg {...base(p)}><path d="M3 11 22 2 13 21 11 13 3 11z" /></svg>
);
export const IconInbox = (p: IconProps) => (
  <svg {...base(p)}><path d="M22 12h-6l-2 3h-4l-2-3H2" /><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z" /></svg>
);
export const IconClipboard = (p: IconProps) => (
  <svg {...base(p)}><rect x="8" y="2" width="8" height="4" rx="1" /><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2" /><path d="m9 14 2 2 4-4" /></svg>
);
export const IconMessages = (p: IconProps) => (
  <svg {...base(p)}><path d="M14 9a2 2 0 0 1-2 2H6l-4 4V4a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2z" /><path d="M18 9h2a2 2 0 0 1 2 2v11l-4-4h-6a2 2 0 0 1-2-2v-1" /></svg>
);
export const IconBell = (p: IconProps) => (
  <svg {...base(p)}><path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9" /><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0" /></svg>
);
export const IconCheck = (p: IconProps) => (
  <svg {...base(p)}><path d="M20 6 9 17l-5-5" /></svg>
);

// The juncture mark — two arcs and two bars, colourable.
// The askandgo mark (final, Scott 2026-10-30, « A bis 20° flèche 20° »): a
// speech bubble whose tail leaves at 20°, a question mark, and an arrowhead in
// the tail's axis — ask, then go. The arrow stroke is 0.75 × the bubble's.
export function AskandgoMark({ size = 30, color = '#FFFFFF' }: { size?: number; color?: string }) {
  return (
    <svg width={size} height={size} viewBox="0 2 100 100" fill="none" stroke={color} strokeWidth="9" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M36.24 74.34 L38.56 67.95 A6 6 0 0 1 44.2 64 H74 A16 16 0 0 0 90 48 V28 A16 16 0 0 0 74 12 H34 A16 16 0 0 0 18 28 V38 C18 44 20 47 25 52" />
      <path d="M24.36 80.09 L29.86 91.88 L41.65 86.38" strokeWidth="6.75" />
    </svg>
  );
}
