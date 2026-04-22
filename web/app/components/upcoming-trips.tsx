import { NAVY, ORANGE, SectionLabel, TopoLines } from './shared';

const TRIPS = [
  {
    sport: 'Escalade',
    emoji: '🧗',
    location: 'Calanques, Marseille',
    date: 'Dim. 27 avr',
    time: '9h',
    level: 'Tous niveaux',
    detail: '6a → 7a',
    participants: 4,
    max: 6,
    accent: '#F26B2E',
  },
  {
    sport: 'Parapente',
    emoji: '🪂',
    location: 'Col de la Forclaz, Annecy',
    date: 'Sam. 3 mai',
    time: '7h30',
    level: 'Pilote autonome',
    detail: 'Déniv. 900 m',
    participants: 3,
    max: 5,
    accent: '#4B7CB8',
  },
  {
    sport: 'Trail',
    emoji: '🏃',
    location: 'Belledonne, Grenoble',
    date: 'Dim. 4 mai',
    time: '8h',
    level: 'Confirmé',
    detail: '25 km · D+ 1 400 m',
    participants: 6,
    max: 10,
    accent: '#7EC8A3',
  },
  {
    sport: 'Ski de rando',
    emoji: '🎿',
    location: 'Vallée Blanche, Chamonix',
    date: 'Sam. 10 mai',
    time: '5h30',
    level: 'Confirmé',
    detail: 'D+ 1 200 m',
    participants: 2,
    max: 4,
    accent: '#F4A373',
  },
];

export default function UpcomingTrips() {
  return (
    <section
      id="sorties"
      className="junto-trips"
      style={{
        padding: '140px 40px',
        background: 'var(--cream-soft)',
        position: 'relative',
        overflow: 'hidden',
      }}
    >
      <TopoLines opacity={0.04} color={NAVY} count={10} />
      <div style={{ maxWidth: 1180, margin: '0 auto', position: 'relative' }}>
        <div style={{ marginBottom: 64, maxWidth: 720 }}>
          <SectionLabel>Cette semaine</SectionLabel>
          <h2
            className="display junto-trips-title"
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
            Des sorties, <span style={{ color: ORANGE }}>en vrai.</span>
          </h2>
        </div>

        <div
          className="junto-trips-grid"
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))',
            gap: 20,
          }}
        >
          {TRIPS.map((t, i) => (
            <div
              key={i}
              className="junto-trips-card"
              style={{
                background: '#FFF',
                border: '1px solid var(--line)',
                borderRadius: 20,
                padding: 28,
                display: 'grid',
                gridTemplateColumns: '64px minmax(0, 1fr) auto',
                gap: 20,
                alignItems: 'center',
              }}
            >
              <div
                className="junto-trips-emoji"
                style={{
                  width: 64,
                  height: 64,
                  borderRadius: 16,
                  background: t.accent + '22',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontSize: 30,
                }}
              >
                {t.emoji}
              </div>
              <div style={{ minWidth: 0 }}>
                <div
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: 10,
                    marginBottom: 6,
                    flexWrap: 'wrap',
                  }}
                >
                  <span
                    className="mono"
                    style={{
                      fontSize: 11,
                      fontWeight: 600,
                      color: t.accent,
                      textTransform: 'uppercase',
                      letterSpacing: '0.12em',
                    }}
                  >
                    {t.sport}
                  </span>
                  <span
                    style={{
                      width: 3,
                      height: 3,
                      borderRadius: '50%',
                      background: 'var(--muted)',
                    }}
                  />
                  <span style={{ fontSize: 13, color: 'var(--muted)' }}>{t.level}</span>
                  <span
                    style={{
                      width: 3,
                      height: 3,
                      borderRadius: '50%',
                      background: 'var(--muted)',
                    }}
                  />
                  <span style={{ fontSize: 13, color: 'var(--muted)' }}>{t.detail}</span>
                </div>
                <h3
                  className="display junto-trips-card-title"
                  style={{
                    fontSize: 22,
                    margin: '0 0 6px',
                    fontWeight: 800,
                    color: NAVY,
                    letterSpacing: '-0.02em',
                  }}
                >
                  {t.location}
                </h3>
                <div style={{ fontSize: 13, color: 'var(--muted)', display: 'flex', gap: 10 }}>
                  <span>{t.date}</span>
                  <span>·</span>
                  <span>{t.time}</span>
                </div>
              </div>
              <div style={{ textAlign: 'right' }}>
                <div
                  className="display"
                  style={{
                    fontSize: 26,
                    fontWeight: 800,
                    color: NAVY,
                    letterSpacing: '-0.02em',
                  }}
                >
                  {t.participants}/{t.max}
                </div>
                <div
                  className="mono"
                  style={{
                    fontSize: 10,
                    color: 'var(--muted)',
                    letterSpacing: '0.1em',
                    textTransform: 'uppercase',
                  }}
                >
                  Partants
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
