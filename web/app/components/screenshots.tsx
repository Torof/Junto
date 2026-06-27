import { CREAM, NAVY_DEEP, ORANGE_SOFT, SectionLabel, TopoLines } from './shared';

const SCREENS = [
  {
    src: '/screenshots/1-map.jpeg',
    title: 'La carte',
    desc: "Les sorties près de toi, d'un coup d'œil.",
    alt: 'Carte des activités autour de toi',
  },
  {
    src: '/screenshots/2-activity.jpeg',
    title: "L'activité",
    desc: "Niveau, places, départ — toutes les infos pour t'engager.",
    alt: "Détail d'une activité",
  },
  {
    src: '/screenshots/3-transport.jpeg',
    title: 'Le transport',
    desc: "Qui conduit, qui monte. Le covoiturage s'organise en deux clics.",
    alt: 'Covoiturage et préparatifs de transport',
  },
  {
    src: '/screenshots/4-gear.jpeg',
    title: 'Le matériel',
    desc: "Qui apporte quoi. Plus d'oubli, plus de doublon.",
    alt: 'Inventaire de matériel partagé',
  },
  {
    src: '/screenshots/5-chat.jpeg',
    title: 'La discussion',
    desc: 'Un fil par sortie. Fini les groupes WhatsApp interminables.',
    alt: "Chat de l'activité",
  },
  {
    src: '/screenshots/6-pro.jpeg',
    title: 'La page pro',
    desc: 'Moniteurs et guides : offres et avis réunis.',
    alt: "Page d'un professionnel",
  },
  {
    src: '/screenshots/7-profile.jpeg',
    title: 'Le profil',
    desc: "Fiabilité et badges : tu sais à qui tu as affaire, même entre inconnus.",
    alt: 'Profil, fiabilité et badges',
  },
];

export default function Screenshots() {
  return (
    <section
      className="junto-shots"
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
            className="display junto-shots-title"
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
          className="junto-shots-grid"
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))',
            gap: 28,
          }}
        >
          {SCREENS.map((s, i) => (
            <div key={s.src}>
              <div
                className={`junto-shots-frame ${i % 2 === 0 ? 'junto-shots-frame-even' : 'junto-shots-frame-odd'}`}
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
                    aspectRatio: '981 / 2048',
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
                <p
                  style={{
                    margin: '8px auto 0',
                    maxWidth: 260,
                    fontSize: 14,
                    lineHeight: 1.4,
                    color: 'rgba(255,255,255,0.6)',
                    textWrap: 'balance',
                  }}
                >
                  {s.desc}
                </p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
