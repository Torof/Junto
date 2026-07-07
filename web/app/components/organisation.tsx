import { NAVY, ORANGE, SectionLabel, TopoLines } from './shared';

// Replaces the Screenshots section (Scott 2026-07-07): the four logistics
// pillars that make Junto an organizer, not a social feed. Tone brief:
// "expliqué simplement, sans chichis — montrer la puissance, pas en faire
// trop". Each card leads with a REAL app screenshot (proof by product —
// emojis and bare text both failed to stop the eye), title + one line below.

const PILLARS: { image: string; title: string; body: string }[] = [
  {
    image: '/feat-transport.jpg',
    title: 'Transport',
    body: 'Qui part d’où, à quelle heure, avec combien de places. Le covoiturage est intégré à chaque sortie.',
  },
  {
    image: '/feat-materiel.jpg',
    title: 'Matériel',
    body: 'La liste de matos vit dans la sortie : qui apporte la corde, qui cherche un casque. On part complet.',
  },
  {
    image: '/feat-chat.jpg',
    title: 'Chat',
    body: 'Un groupe par sortie, créé tout seul, avec les bonnes personnes dedans. Rien à échanger, rien à installer.',
  },
  {
    image: '/feat-profil.jpg',
    title: 'Profil',
    body: 'Tes sports, tes niveaux, ta fiabilité. Tu sais avec qui tu pars — et venir vraiment, ça se voit.',
  },
];

export default function Organisation() {
  return (
    <section
      className="junto-orga"
      style={{
        padding: '110px 40px',
        background: 'var(--cream)',
        position: 'relative',
        overflow: 'hidden',
      }}
    >
      <TopoLines opacity={0.05} color={NAVY} count={9} />
      <div style={{ maxWidth: 1180, margin: '0 auto', position: 'relative' }}>
        <div style={{ marginBottom: 48, maxWidth: 780 }}>
          <SectionLabel>La logistique</SectionLabel>
          <h2
            className="display junto-orga-title"
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
            S'organiser n'a jamais été <span style={{ color: ORANGE }}>aussi simple</span>.
          </h2>
          <p style={{ fontSize: 18, lineHeight: 1.55, margin: '18px 0 0', color: 'var(--muted)', maxWidth: 640 }}>
            Une sortie, ce n'est pas que des partants : il faut répartir les voitures, le matos,
            se parler. Sur Junto, tout ça vit directement dans la sortie.
          </p>
        </div>

        <div
          className="junto-orga-grid"
          style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', gap: 16 }}
        >
          {PILLARS.map((p) => (
            <div
              key={p.title}
              style={{
                background: '#FFF',
                border: '1px solid var(--line)',
                borderRadius: 16,
                overflow: 'hidden',
                display: 'flex',
                flexDirection: 'column',
              }}
            >
              {/* Real app screenshot — cropped window, status bar and tab
                  header trimmed by the top offset. */}
              <div style={{ height: 300, position: 'relative', overflow: 'hidden', borderBottom: '1px solid var(--line)', flexShrink: 0 }}>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={p.image}
                  alt={`Écran ${p.title} de l'app Junto`}
                  style={{
                    position: 'absolute',
                    inset: 0,
                    width: '100%',
                    height: '100%',
                    objectFit: 'cover',
                    objectPosition: '50% 22%',
                  }}
                />
              </div>
              <div style={{ padding: '22px 22px 26px' }}>
                <div
                  className="display"
                  style={{ fontSize: 21, fontWeight: 800, color: NAVY, letterSpacing: '-0.02em', marginBottom: 8 }}
                >
                  {p.title}
                </div>
                <p style={{ fontSize: 15, lineHeight: 1.55, margin: 0, color: 'var(--muted)' }}>{p.body}</p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
