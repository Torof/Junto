import { NAVY, ORANGE, SectionLabel, TopoLines } from './shared';

// Replaces the Screenshots section (Scott 2026-07-07): the four logistics
// pillars that make Junto an organizer, not a social feed. Tone brief:
// "expliqué simplement, sans chichis — montrer la puissance, pas en faire
// trop". Four flat cards, two plain sentences each, no mockups.

const PILLARS: { icon: string; title: string; body: string }[] = [
  {
    icon: '🚗',
    title: 'Transport',
    body: 'Qui part d’où, à quelle heure, avec combien de places. Le covoiturage est intégré à chaque sortie.',
  },
  {
    icon: '🎒',
    title: 'Matériel',
    body: 'La liste de matos vit dans la sortie : qui apporte la corde, qui cherche un casque. On part complet.',
  },
  {
    icon: '💬',
    title: 'Chat',
    body: 'Un groupe par sortie, créé tout seul, avec les bonnes personnes dedans. Rien à échanger, rien à installer.',
  },
  {
    icon: '⛰️',
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
                padding: '26px 24px',
              }}
            >
              <span
                style={{
                  width: 44,
                  height: 44,
                  borderRadius: 12,
                  background: ORANGE + '1E',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontSize: 21,
                  marginBottom: 16,
                }}
              >
                {p.icon}
              </span>
              <div
                className="display"
                style={{ fontSize: 21, fontWeight: 800, color: NAVY, letterSpacing: '-0.02em', marginBottom: 8 }}
              >
                {p.title}
              </div>
              <p style={{ fontSize: 15, lineHeight: 1.55, margin: 0, color: 'var(--muted)' }}>{p.body}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
