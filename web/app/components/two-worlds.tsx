import { NAVY, ORANGE, SectionLabel, TopoLines } from './shared';

// Layer-2 "glance" section: each world is shown as the SAME map carrying
// its own pins — orange teardrops (peer activities) vs the blue pro layer.
// Real map crops from the app; the orange/blue split is the page-wide
// color code. Makes "une carte, deux mondes" literal and on-brand.

const PRO_BLUE = '#3b82f6';

const WORLDS = [
  {
    accent: ORANGE,
    kicker: 'Entre particuliers',
    body: 'Trouve, crée et rejoins des sorties avec d’autres passionnés près de chez toi. Covoiturage, matos, chat — tout au même endroit.',
    image: '/screenshots/world-particuliers.jpeg',
    alt: 'Carte avec des sorties entre particuliers',
    // Taller-content crop: show it whole (contain) so no pin is clipped;
    // the banner bg is the map's own green so the side bands blend in.
    fit: 'contain' as const,
    bg: '#88BD6F',
  },
  {
    accent: PRO_BLUE,
    kicker: 'Avec des pros',
    body: 'Guides diplômés, écoles, moniteurs — vérifiés, avec leur catalogue de prestations posé directement sur la carte.',
    image: '/screenshots/world-pros.jpeg',
    alt: 'Carte avec une page pro et son offre',
    fit: 'cover' as const,
    bg: 'transparent',
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
              <div
                style={{
                  height: 180,
                  position: 'relative',
                  borderBottom: `1px solid var(--line)`,
                  background: w.bg,
                }}
              >
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={w.image}
                  alt={w.alt}
                  style={{ width: '100%', height: '100%', objectFit: w.fit, objectPosition: 'center', display: 'block' }}
                />
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
