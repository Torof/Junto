import { NAVY, ORANGE, SectionLabel, TopoLines } from './shared';

// Layer-2 "glance" section (added 2026-06-11): frames Junto's core
// duality — peers + pros on one map — in a single side-by-side beat,
// so the user/pro distinction is instant before the deep-dive sections.
// Establishes the page-wide color language: orange = particuliers,
// blue = pros (mirrors the map's activity vs pro-pin colors).

const PRO_BLUE = '#3b82f6';

const WORLDS = [
  {
    accent: ORANGE,
    chip: '🤝',
    kicker: 'Entre particuliers',
    body: 'Trouve, crée et rejoins des sorties avec d’autres passionnés près de chez toi. Covoiturage, matos, chat — tout au même endroit.',
  },
  {
    accent: PRO_BLUE,
    chip: '✓',
    kicker: 'Avec des pros',
    body: 'Guides diplômés, écoles, moniteurs — vérifiés à la main, avec leur catalogue de prestations posé directement sur la carte.',
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
            Des particuliers <span style={{ color: ORANGE }}>et</span> des{' '}
            <span style={{ color: PRO_BLUE }}>pros</span>, sur la même carte.
          </h2>
        </div>

        <div
          className="junto-worlds-grid"
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(2, minmax(0, 1fr))',
            gap: 24,
          }}
        >
          {WORLDS.map((w) => (
            <div
              key={w.kicker}
              style={{
                background: '#FFF',
                border: '1px solid var(--line)',
                borderTop: `4px solid ${w.accent}`,
                borderRadius: 20,
                padding: '40px 36px',
              }}
            >
              <div
                style={{
                  width: 52,
                  height: 52,
                  borderRadius: 14,
                  background: w.accent + '1E',
                  color: w.accent,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontSize: 24,
                  fontWeight: 800,
                  marginBottom: 22,
                }}
              >
                {w.chip}
              </div>
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
              <p style={{ fontSize: 17, lineHeight: 1.55, margin: 0, color: 'var(--muted)' }}>
                {w.body}
              </p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
