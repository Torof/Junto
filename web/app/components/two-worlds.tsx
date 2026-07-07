import { NAVY, ORANGE, SectionLabel, TopoLines } from './shared';
import { UaPin, RaPin, PpPin, PRO_BLUE } from './map-pins';

// Layer-2 "glance" section: each world is shown as the SAME kind of map
// carrying its own pins — stone teardrops (peer outings) vs the blue pro
// layer (PRO offerings + pushpin storefronts). Real Mapbox outdoors
// fragments (Queyras / Serre-Ponçon) with the app's exact pin SVGs
// overlaid, replacing the old app screenshots (Scott 2026-07-07).

const WORLDS = [
  {
    accent: ORANGE,
    kicker: 'Entre passionnés',
    body: 'Trouve, crée et rejoins des sorties avec d’autres passionnés près de chez toi. Covoiturage, matos, chat — tout au même endroit.',
    image: '/world-map-passionnes.jpg',
    alt: 'Carte avec des sorties entre passionnés',
    pins: [
      { left: '22%', top: '62%', node: <UaPin emoji="🚵" /> },
      { left: '48%', top: '38%', node: <UaPin emoji="🥾" /> },
      { left: '74%', top: '66%', node: <UaPin emoji="🧗" /> },
    ],
  },
  {
    accent: PRO_BLUE,
    kicker: 'Encadré par un pro',
    body: 'Guides diplômés, écoles, moniteurs — vérifiés, avec leur catalogue de prestations posé directement sur la carte.',
    image: '/world-map-pros.jpg',
    alt: 'Carte avec des sorties encadrées par des pros',
    pins: [
      { left: '30%', top: '58%', node: <RaPin emoji="🚣" /> },
      { left: '72%', top: '44%', node: <RaPin emoji="🏔️" /> },
      { left: '52%', top: '70%', node: <PpPin /> },
    ],
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
            Des <span style={{ color: ORANGE }}>passionnés</span> et des{' '}
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
                role="img"
                aria-label={w.alt}
                style={{
                  height: 180,
                  position: 'relative',
                  borderBottom: `1px solid var(--line)`,
                  overflow: 'hidden',
                }}
              >
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={w.image}
                  alt=""
                  style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover', display: 'block' }}
                />
                {w.pins.map((p, i) => (
                  <div key={i} className="junto-hero-pin" style={{ left: p.left, top: p.top, width: 44 }}>
                    {p.node}
                  </div>
                ))}
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
