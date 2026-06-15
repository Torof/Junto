import { NAVY, NAVY_DEEP, ORANGE, Pin, SectionLabel, TopoLines } from './shared';

// Layer-2 "glance" section (reworked 2026-06-11): instead of two plain
// text cards, each world is shown as the SAME map terrain carrying its
// own pins — orange teardrops (peer activities) vs a blue pushpin +
// blue offering (the pro layer). Makes "une carte, deux mondes" literal
// and on-brand, and the orange/blue split is the page-wide color code.

const PRO_BLUE = '#3b82f6';
const TERRAIN = '#EFE4CE';

// Pro storefront pushpin — round head on a needle (mirrors the app's PP
// pin). Rendered inside the scene <svg>.
function Pushpin({ x, y }: { x: number; y: number }) {
  const headY = y - 40;
  return (
    <g>
      <ellipse cx={x} cy={y} rx={7} ry={2.5} fill="#000" opacity={0.18} />
      <path d={`M ${x - 3.5} ${headY} L ${x} ${y} L ${x + 3.5} ${headY} Z`} fill={NAVY_DEEP} />
      <circle cx={x} cy={headY} r={22} fill={PRO_BLUE} stroke="#F5F5F0" strokeWidth={2.5} />
      <text x={x} y={headY + 1} textAnchor="middle" fontSize="20" dominantBaseline="middle">
        🏔️
      </text>
    </g>
  );
}

function Terrain() {
  return (
    <>
      <rect width="320" height="180" fill={TERRAIN} />
      <g fill="none" stroke="#D9CDB4" strokeWidth="1.2" opacity="0.7">
        <path d="M -10 50 Q 100 30 180 60 T 330 42" />
        <path d="M -10 100 Q 120 82 200 112 T 330 92" />
        <path d="M -10 150 Q 110 134 190 158 T 330 144" />
      </g>
      <path
        d="M 0 80 Q 100 62 180 92 T 320 72"
        fill="none"
        stroke="#B8D1E3"
        strokeWidth="5"
        opacity="0.55"
      />
    </>
  );
}

function ParticuliersScene() {
  return (
    <svg viewBox="0 0 320 180" preserveAspectRatio="xMidYMid slice" style={{ width: '100%', height: '100%' }}>
      <Terrain />
      <Pin x={70} y={132} color={ORANGE} emoji="🥾" />
      <Pin x={165} y={98} color={ORANGE} emoji="🧗" />
      <Pin x={250} y={150} color={ORANGE} emoji="🚵" />
    </svg>
  );
}

function ProsScene() {
  return (
    <svg viewBox="0 0 320 180" preserveAspectRatio="xMidYMid slice" style={{ width: '100%', height: '100%' }}>
      <Terrain />
      <Pin x={235} y={140} color={PRO_BLUE} emoji="🛶" />
      <Pushpin x={120} y={150} />
    </svg>
  );
}

const WORLDS = [
  {
    accent: ORANGE,
    kicker: 'Entre particuliers',
    body: 'Trouve, crée et rejoins des sorties avec d’autres passionnés près de chez toi. Covoiturage, matos, chat — tout au même endroit.',
    Scene: ParticuliersScene,
  },
  {
    accent: PRO_BLUE,
    kicker: 'Avec des pros',
    body: 'Guides diplômés, écoles, moniteurs — vérifiés à la main, avec leur catalogue de prestations posé directement sur la carte.',
    Scene: ProsScene,
  },
];

export default function TwoWorlds() {
  return (
    <section
      className="junto-worlds"
      style={{
        padding: '120px 40px',
        background: 'var(--cream)',
        position: 'relative',
        overflow: 'hidden',
      }}
    >
      <TopoLines opacity={0.05} color={NAVY} count={9} />
      <div style={{ maxWidth: 1180, margin: '0 auto', position: 'relative' }}>
        <div style={{ marginBottom: 56, maxWidth: 760 }}>
          <SectionLabel>Une carte, deux mondes</SectionLabel>
          <h2
            className="display junto-worlds-title"
            style={{
              fontSize: 'clamp(40px, 6vw, 64px)',
              lineHeight: 0.98,
              margin: 0,
              fontWeight: 800,
              letterSpacing: '-0.035em',
              color: NAVY,
              textWrap: 'balance',
            }}
          >
            Des <span style={{ color: ORANGE }}>particuliers</span> et des{' '}
            <span style={{ color: PRO_BLUE }}>pros</span>, sur la même carte.
          </h2>
        </div>

        <div
          className="junto-worlds-grid"
          style={{ display: 'grid', gridTemplateColumns: 'repeat(2, minmax(0, 1fr))', gap: 24 }}
        >
          {WORLDS.map((w) => (
            <div
              key={w.kicker}
              style={{
                background: '#FFF',
                border: `2px solid ${w.accent}`,
                borderRadius: 20,
                overflow: 'hidden',
                display: 'flex',
                flexDirection: 'column',
              }}
            >
              <div style={{ height: 180, position: 'relative', borderBottom: `1px solid var(--line)` }}>
                <w.Scene />
              </div>
              <div style={{ padding: '32px 36px 38px' }}>
                <h3
                  className="display"
                  style={{
                    fontSize: 30,
                    margin: '0 0 12px',
                    fontWeight: 800,
                    letterSpacing: '-0.025em',
                    color: w.accent,
                  }}
                >
                  {w.kicker}
                </h3>
                <p style={{ fontSize: 17, lineHeight: 1.55, margin: 0, color: 'var(--muted)' }}>{w.body}</p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
