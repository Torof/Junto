import { CREAM, NAVY_DEEP, ORANGE_SOFT, SectionLabel, TopoLines } from './shared';

const SCREENS = [
  { src: '/screenshots/1-map.jpeg', title: 'La carte', alt: 'Carte des activités' },
  { src: '/screenshots/2-popup.jpeg', title: 'Un aperçu', alt: "Aperçu d'une activité" },
  { src: '/screenshots/3-activity.jpeg', title: 'Le détail', alt: "Page d'activité" },
  { src: '/screenshots/4-profile.jpeg', title: 'Le profil', alt: 'Profil utilisateur' },
];

export default function Screenshots() {
  return (
    <section
      style={{
        padding: '140px 40px',
        background: NAVY_DEEP,
        color: '#FFF',
        overflow: 'hidden',
        position: 'relative',
      }}
    >
      <TopoLines opacity={0.04} color={CREAM} count={8} />
      <div style={{ maxWidth: 1280, margin: '0 auto', position: 'relative' }}>
        <div style={{ marginBottom: 80, maxWidth: 720 }}>
          <SectionLabel color={ORANGE_SOFT}>L&apos;app</SectionLabel>
          <h2
            className="display"
            style={{
              fontSize: 'clamp(40px, 6vw, 64px)',
              lineHeight: 0.98,
              margin: 0,
              fontWeight: 800,
              letterSpacing: '-0.035em',
              textWrap: 'balance',
            }}
          >
            Pensée pour le <span style={{ color: ORANGE_SOFT }}>terrain.</span>
          </h2>
        </div>

        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))',
            gap: 28,
          }}
        >
          {SCREENS.map((s, i) => (
            <div key={s.src}>
              <div
                style={{
                  borderRadius: 32,
                  padding: 8,
                  background: 'linear-gradient(180deg, #2A3E5F 0%, #182238 100%)',
                  boxShadow:
                    '0 40px 60px -20px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,255,255,0.08)',
                  transform: i % 2 === 0 ? 'translateY(0)' : 'translateY(28px)',
                }}
              >
                <div
                  style={{
                    borderRadius: 26,
                    overflow: 'hidden',
                    aspectRatio: '1080 / 2020',
                    background: '#000',
                  }}
                >
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    src={s.src}
                    alt={s.alt}
                    style={{
                      width: '100%',
                      height: '100%',
                      objectFit: 'contain',
                      objectPosition: 'top',
                      display: 'block',
                    }}
                  />
                </div>
              </div>
              <div style={{ padding: '28px 8px 0', textAlign: 'center' }}>
                <div
                  className="mono"
                  style={{
                    fontSize: 10,
                    color: ORANGE_SOFT,
                    letterSpacing: '0.15em',
                    marginBottom: 6,
                  }}
                >
                  0{i + 1}
                </div>
                <div
                  className="display"
                  style={{ fontSize: 20, fontWeight: 800, letterSpacing: '-0.02em' }}
                >
                  {s.title}
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
