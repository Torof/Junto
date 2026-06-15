import { NAVY, ORANGE, SectionLabel, TopoLines } from './shared';

// Condensed 2026-06-11 (Scott: full per-sport enumeration took too much
// space / too much info). Now category chips with a count + two
// examples each — keeps the breadth proof, drops the exhaustive list.
const CATEGORIES: { name: string; accent: string; count: number; sample: string }[] = [
  { name: 'Montagne', accent: '#F26B2E', count: 9, sample: 'Escalade, alpinisme…' },
  { name: 'Eau', accent: '#4B7CB8', count: 7, sample: 'Kayak, surf…' },
  { name: 'Neige', accent: '#9DB7D4', count: 3, sample: 'Ski, snowboard…' },
  { name: 'Air', accent: '#F4A373', count: 2, sample: 'Parapente, parachutisme' },
  { name: 'Vélo', accent: '#7EC8A3', count: 2, sample: 'Vélo, VTT' },
  { name: 'Terrain', accent: '#D4B46A', count: 10, sample: 'Course, tennis…' },
];

export default function Sports() {
  const total = CATEGORIES.reduce((n, c) => n + c.count, 0);

  return (
    <section
      className="junto-sports"
      style={{
        padding: '110px 40px',
        background: 'var(--cream)',
        position: 'relative',
        overflow: 'hidden',
      }}
    >
      <TopoLines opacity={0.05} color={NAVY} count={10} />
      <div style={{ maxWidth: 1180, margin: '0 auto', position: 'relative' }}>
        <div style={{ marginBottom: 48, maxWidth: 820 }}>
          <SectionLabel>Les sports</SectionLabel>
          <h2
            className="display junto-sports-title"
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
            <span style={{ color: ORANGE }}>{total} sports</span>, 6 univers — et ça grandit.
          </h2>
        </div>

        <div
          className="junto-sports-grid"
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))',
            gap: 16,
          }}
        >
          {CATEGORIES.map((cat) => (
            <div
              key={cat.name}
              style={{
                background: '#FFF',
                border: '1px solid var(--line)',
                borderRadius: 16,
                padding: '20px 22px',
                display: 'flex',
                alignItems: 'center',
                gap: 14,
              }}
            >
              <span
                style={{ width: 12, height: 12, borderRadius: '50%', background: cat.accent, flexShrink: 0 }}
              />
              <div style={{ minWidth: 0, flex: 1 }}>
                <div
                  className="display"
                  style={{ fontSize: 18, fontWeight: 800, color: NAVY, letterSpacing: '-0.02em', lineHeight: 1.1 }}
                >
                  {cat.name}
                </div>
                <div className="mono" style={{ fontSize: 11, color: 'var(--muted)', letterSpacing: '0.04em', marginTop: 2 }}>
                  {cat.sample}
                </div>
              </div>
              <span
                className="display"
                style={{ fontSize: 22, fontWeight: 800, color: cat.accent, letterSpacing: '-0.02em' }}
              >
                {cat.count}
              </span>
            </div>
          ))}
        </div>

        <div style={{ marginTop: 28, fontSize: 14, color: 'var(--muted)' }}>
          Un sport manque ?{' '}
          <a href="mailto:contact@getjunto.app" style={{ color: ORANGE, textDecoration: 'underline' }}>
            Dis-le nous
          </a>
          .
        </div>
      </div>
    </section>
  );
}
