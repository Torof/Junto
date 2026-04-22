import { NAVY, ORANGE, SectionLabel, TopoLines } from './shared';

const CATEGORIES = [
  {
    name: 'Montagne',
    accent: '#F26B2E',
    sports: [
      'Randonnée',
      'Escalade',
      'Ski de rando',
      'Trail',
      'Alpinisme',
      'Via ferrata',
      'Cascade de glace',
      'Canyoning',
      'Slackline',
    ],
  },
  {
    name: 'Eau',
    accent: '#4B7CB8',
    sports: ['Kayak', 'Surf', 'Voile', 'Stand-up Paddle', 'Rafting', 'Plongée', 'Natation'],
  },
  {
    name: 'Neige',
    accent: '#9DB7D4',
    sports: ['Ski', 'Snowboard', 'Ski de fond'],
  },
  {
    name: 'Air',
    accent: '#F4A373',
    sports: ['Parapente', 'Parachutisme'],
  },
  {
    name: 'Vélo',
    accent: '#7EC8A3',
    sports: ['Vélo', 'VTT'],
  },
  {
    name: 'Terrain',
    accent: '#D4B46A',
    sports: [
      'Course à pied',
      'Football',
      'Tennis',
      'Volleyball',
      'Badminton',
      'Équitation',
      'Skateboard',
      'Triathlon',
      'CrossFit',
      'Pêche en roche',
    ],
  },
];

export default function Sports() {
  const total = CATEGORIES.reduce((n, c) => n + c.sports.length, 0);

  return (
    <section
      className="junto-sports"
      style={{
        padding: '140px 40px',
        background: 'var(--cream)',
        position: 'relative',
        overflow: 'hidden',
      }}
    >
      <TopoLines opacity={0.05} color={NAVY} count={10} />
      <div style={{ maxWidth: 1180, margin: '0 auto', position: 'relative' }}>
        <div style={{ marginBottom: 72, maxWidth: 820 }}>
          <SectionLabel>Catalogue</SectionLabel>
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
            <span style={{ color: ORANGE }}>{total} sports</span> — et ça grandit.
          </h2>
        </div>

        <div
          style={{
            display: 'flex',
            flexDirection: 'column',
            gap: 0,
            borderTop: '1px solid rgba(30,47,77,0.12)',
          }}
        >
          {CATEGORIES.map((cat, i) => (
            <div
              key={i}
              className="junto-sports-row"
              style={{
                display: 'grid',
                gridTemplateColumns: 'minmax(180px, 200px) minmax(0, 1fr)',
                gap: 40,
                padding: '32px 0',
                borderBottom: '1px solid rgba(30,47,77,0.12)',
                alignItems: 'baseline',
              }}
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                <span
                  style={{
                    width: 10,
                    height: 10,
                    borderRadius: '50%',
                    background: cat.accent,
                    flexShrink: 0,
                  }}
                />
                <span
                  className="display"
                  style={{
                    fontSize: 22,
                    fontWeight: 800,
                    color: NAVY,
                    letterSpacing: '-0.02em',
                  }}
                >
                  {cat.name}
                </span>
                <span
                  className="mono"
                  style={{ fontSize: 11, color: 'var(--muted)', letterSpacing: '0.1em' }}
                >
                  {String(cat.sports.length).padStart(2, '0')}
                </span>
              </div>

              <div
                className="junto-sports-list"
                style={{
                  display: 'flex',
                  flexWrap: 'wrap',
                  gap: '12px 20px',
                  fontSize: 17,
                  fontWeight: 500,
                  color: NAVY,
                  lineHeight: 1.4,
                }}
              >
                {cat.sports.map((s, j) => (
                  <span key={j} style={{ display: 'inline-flex', alignItems: 'center' }}>
                    {s}
                    {j < cat.sports.length - 1 && (
                      <span style={{ marginLeft: 20, color: 'rgba(30,47,77,0.2)' }}>·</span>
                    )}
                  </span>
                ))}
              </div>
            </div>
          ))}
        </div>

        <div style={{ marginTop: 32, fontSize: 14, color: 'var(--muted)' }}>
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
