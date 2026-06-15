import { NAVY, ORANGE, SectionLabel, TopoLines } from './shared';

// Chips are the glanceable default (count + 2 examples); a native
// <details> unfold reveals the full per-category list — so "7 sports"
// actually delivers all 7 on demand (Scott 2026-06-11), no JS.
const CATEGORIES: { name: string; accent: string; sample: string; sports: string[] }[] = [
  {
    name: 'Montagne',
    accent: '#F26B2E',
    sample: 'Escalade, alpinisme…',
    sports: ['Randonnée', 'Escalade', 'Ski de rando', 'Trail', 'Alpinisme', 'Via ferrata', 'Cascade de glace', 'Canyoning', 'Slackline'],
  },
  {
    name: 'Eau',
    accent: '#4B7CB8',
    sample: 'Kayak, surf…',
    sports: ['Kayak', 'Surf', 'Voile', 'Stand-up Paddle', 'Rafting', 'Plongée', 'Natation'],
  },
  {
    name: 'Neige',
    accent: '#9DB7D4',
    sample: 'Ski, snowboard…',
    sports: ['Ski', 'Snowboard', 'Ski de fond'],
  },
  {
    name: 'Air',
    accent: '#F4A373',
    sample: 'Parapente, parachutisme',
    sports: ['Parapente', 'Parachutisme'],
  },
  {
    name: 'Vélo',
    accent: '#7EC8A3',
    sample: 'Vélo, VTT',
    sports: ['Vélo', 'VTT'],
  },
  {
    name: 'Terrain',
    accent: '#D4B46A',
    sample: 'Course, tennis…',
    sports: ['Course à pied', 'Football', 'Tennis', 'Volleyball', 'Badminton', 'Équitation', 'Skateboard', 'Triathlon', 'CrossFit', 'Pêche en roche'],
  },
];

export default function Sports() {
  const total = CATEGORIES.reduce((n, c) => n + c.sports.length, 0);

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
          style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', gap: 16 }}
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
              <span style={{ width: 12, height: 12, borderRadius: '50%', background: cat.accent, flexShrink: 0 }} />
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
                {cat.sports.length}
              </span>
            </div>
          ))}
        </div>

        <details className="junto-sports-more" style={{ marginTop: 24 }}>
          <summary
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: 8,
              cursor: 'pointer',
              fontSize: 14,
              fontWeight: 700,
              color: ORANGE,
              padding: '10px 18px',
              borderRadius: 999,
              border: `1px solid ${ORANGE}55`,
              background: ORANGE + '12',
              userSelect: 'none',
            }}
          >
            Voir les {total} sports
          </summary>

          <div
            className="junto-sports-full"
            style={{
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fit, minmax(260px, 1fr))',
              gap: '24px 40px',
              marginTop: 28,
            }}
          >
            {CATEGORIES.map((cat) => (
              <div key={cat.name}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 10 }}>
                  <span style={{ width: 10, height: 10, borderRadius: '50%', background: cat.accent, flexShrink: 0 }} />
                  <span
                    className="display"
                    style={{ fontSize: 17, fontWeight: 800, color: NAVY, letterSpacing: '-0.02em' }}
                  >
                    {cat.name}
                  </span>
                </div>
                <div style={{ fontSize: 15, lineHeight: 1.7, color: 'var(--muted)' }}>
                  {cat.sports.join(' · ')}
                </div>
              </div>
            ))}
          </div>
        </details>

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
