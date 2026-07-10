import type { CSSProperties, ReactNode } from 'react';

// Color tokens — source of truth mirrored from globals.css for inline use.
export const NAVY = '#1E2F4D';
export const NAVY_DEEP = '#14223B';
export const NAVY_DARK = '#0F1828';
// Brand accent — vert vif #2FA46A (site + app). The standalone juncture logo
// signature is vert montagne #3F7A56. Names kept for a minimal diff.
export const ORANGE = '#2FA46A';
export const ORANGE_SOFT = '#7BC6A0';
export const CREAM = '#F4E9D3';
export const CREAM_SOFT = '#FBF5E6';
export const MINT = '#7EC8A3';
export const SKY = '#4B7CB8';
// Brutalist tokens (hero identity) — shared so the CTA + footer match it.
export const PAPER = '#F5EEDF';
export const INK = '#1F1A15';
export const INK_SOFT = '#4A4034';
export const STONE = '#E0D2B4';

type TopoLinesProps = {
  opacity?: number;
  color?: string;
  count?: number;
};

export function TopoLines({ opacity = 0.08, color = CREAM, count = 14 }: TopoLinesProps) {
  return (
    <svg
      style={{
        position: 'absolute',
        inset: 0,
        width: '100%',
        height: '100%',
        opacity,
        pointerEvents: 'none',
      }}
      preserveAspectRatio="none"
      viewBox="0 0 1400 800"
      aria-hidden
    >
      {Array.from({ length: count }).map((_, i) => {
        const y = 80 + i * 50;
        const a = 40 + (i * 37) % 60;
        const b = 80 + (i * 53) % 100;
        return (
          <path
            key={i}
            d={`M 0 ${y} Q 250 ${y - a} 500 ${y + 20} T 1000 ${y - b * 0.3} T 1400 ${y}`}
            fill="none"
            stroke={color}
            strokeWidth="1.2"
          />
        );
      })}
    </svg>
  );
}

type SectionLabelProps = {
  children: ReactNode;
  color?: string;
  style?: CSSProperties;
};

export function SectionLabel({ children, color, style }: SectionLabelProps) {
  const c = color || ORANGE;
  return (
    <div
      className="mono"
      style={{
        fontSize: 12,
        fontWeight: 500,
        color: c,
        letterSpacing: '0.2em',
        textTransform: 'uppercase',
        display: 'inline-flex',
        alignItems: 'center',
        gap: 12,
        marginBottom: 20,
        ...style,
      }}
    >
      <span style={{ width: 20, height: 1, background: c, opacity: 0.8 }} />
      {children}
    </div>
  );
}

type PinProps = {
  x: number;
  y: number;
  color: string;
  emoji: string;
  dark?: boolean;
};

export function Pin({ x, y, color, emoji, dark = false }: PinProps) {
  const w = 52;
  const h = 64;
  return (
    <g transform={`translate(${x - w / 2}, ${y - h})`}>
      <path
        d={`M ${w / 2} ${h - 2}
            L ${w * 0.3} ${h * 0.7}
            Q 2 ${h * 0.7} 2 ${h * 0.38}
            Q 2 2 ${w / 2} 2
            Q ${w - 2} 2 ${w - 2} ${h * 0.38}
            Q ${w - 2} ${h * 0.7} ${w * 0.7} ${h * 0.7}
            Z`}
        fill={color}
        stroke={NAVY_DEEP}
        strokeWidth="2.5"
      />
      <circle
        cx={w / 2}
        cy={h * 0.38}
        r={h * 0.22}
        fill={dark ? NAVY_DEEP : 'rgba(255,255,255,0.92)'}
      />
      <text x={w / 2} y={h * 0.46} textAnchor="middle" fontSize="18" dominantBaseline="middle">
        {emoji}
      </text>
    </g>
  );
}
