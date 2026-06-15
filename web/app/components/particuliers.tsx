import { NAVY, ORANGE, TopoLines } from './shared';

// "Entre particuliers" deep-dive (2026-06-11): rebuilt to share the Pro
// section's layout (headline + feature rows + mockup + CTA) so the two
// worlds read as one design language — distinction carried by color
// (orange) + light background, not by a different layout. World name is
// the headline (not a small eyebrow) so the section's identity leads.

const FEATURES: { icon: string; title: string; body: string }[] = [
  {
    icon: '🗺️',
    title: 'Trouve',
    body: 'Une carte vivante des sorties autour de toi. Filtre par sport, date, niveau — vois qui part où, quand.',
  },
  {
    icon: '✏️',
    title: 'Crée',
    body: 'Lance ta propre sortie en 30 secondes. Fixe le RDV, le niveau, les places — les autres rejoignent.',
  },
  {
    icon: '🤝',
    title: 'Organise',
    body: 'Covoiturage, chat, matériel — tout vit dans la sortie. Plus de groupes WhatsApp à 40.',
  },
];

// Activity-card mockup — the peer-side counterpart to the pro StorefrontCard.
function ActivityCard() {
  return (
    <div
      className="junto-part-card"
      style={{
        background: '#FFF',
        borderRadius: 24,
        padding: 28,
        boxShadow: '0 30px 60px -20px rgba(30,47,77,0.3)',
        border: '1px solid var(--line)',
        maxWidth: 380,
        width: '100%',
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 18 }}>
        <div
          style={{
            width: 54,
            height: 54,
            borderRadius: 14,
            background: ORANGE + '1E',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            fontSize: 26,
            flexShrink: 0,
          }}
        >
          🧗
        </div>
        <div style={{ minWidth: 0 }}>
          <div
            className="mono"
            style={{ fontSize: 10, color: ORANGE, letterSpacing: '0.12em', fontWeight: 700, marginBottom: 4 }}
          >
            ESCALADE · NIVEAU 5B–6B
          </div>
          <div
            className="display"
            style={{ fontSize: 20, fontWeight: 800, color: NAVY, letterSpacing: '-0.02em', lineHeight: 1.1 }}
          >
            Au soleil — Rocher Baron
          </div>
        </div>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginBottom: 20 }}>
        {[
          ['📅', 'Dim. 14 juin · 8h30'],
          ['📍', 'Départ : parking des Issarts'],
          ['👥', '4 / 6 partants'],
        ].map(([icon, text]) => (
          <div key={text} style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <span
              style={{
                width: 22,
                height: 22,
                borderRadius: 6,
                background: '#F4EBD9',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontSize: 11,
                flexShrink: 0,
              }}
            >
              {icon}
            </span>
            <span style={{ fontSize: 14, color: 'var(--muted)' }}>{text}</span>
          </div>
        ))}
      </div>

      <div
        style={{
          padding: '12px',
          borderRadius: 10,
          background: ORANGE,
          color: '#FFF',
          fontSize: 14,
          fontWeight: 700,
          textAlign: 'center',
        }}
      >
        Rejoindre la sortie
      </div>
    </div>
  );
}

export default function Particuliers() {
  return (
    <section
      id="comment"
      className="junto-part"
      style={{
        padding: '140px 40px',
        background: 'var(--cream-soft)',
        position: 'relative',
        overflow: 'hidden',
      }}
    >
      <TopoLines opacity={0.05} color={ORANGE} count={10} />
      <div
        className="junto-part-grid"
        style={{
          maxWidth: 1180,
          margin: '0 auto',
          position: 'relative',
          display: 'grid',
          gridTemplateColumns: 'minmax(0, 1fr) minmax(0, 420px)',
          gap: 72,
          alignItems: 'center',
        }}
      >
        <div>
          <h2
            className="display junto-part-title"
            style={{
              fontSize: 'clamp(44px, 6.5vw, 68px)',
              lineHeight: 0.98,
              margin: '0 0 16px',
              fontWeight: 800,
              letterSpacing: '-0.035em',
              color: ORANGE,
              textWrap: 'balance',
            }}
          >
            Entre particuliers
          </h2>
          <p
            style={{
              fontSize: 19,
              lineHeight: 1.5,
              margin: '0 0 40px',
              color: NAVY,
              fontWeight: 500,
              maxWidth: 520,
            }}
          >
            Trouve, crée et rejoins des sorties outdoor avec d’autres passionnés, près de chez toi.
          </p>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 22, marginBottom: 40 }}>
            {FEATURES.map((f) => (
              <div key={f.title} style={{ display: 'flex', gap: 16 }}>
                <span
                  style={{
                    width: 34,
                    height: 34,
                    borderRadius: 10,
                    background: ORANGE + '1E',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    fontSize: 16,
                    flexShrink: 0,
                  }}
                >
                  {f.icon}
                </span>
                <div>
                  <div
                    className="display"
                    style={{ fontSize: 19, fontWeight: 800, color: NAVY, letterSpacing: '-0.015em', marginBottom: 3 }}
                  >
                    {f.title}
                  </div>
                  <div style={{ fontSize: 15, lineHeight: 1.5, color: 'var(--muted)', maxWidth: 460 }}>
                    {f.body}
                  </div>
                </div>
              </div>
            ))}
          </div>

          <a
            href="#beta"
            className="junto-part-cta"
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: 10,
              background: ORANGE,
              color: '#FFF',
              padding: '15px 26px',
              borderRadius: 12,
              fontSize: 15,
              fontWeight: 700,
              textDecoration: 'none',
              boxShadow: '0 10px 30px -8px rgba(242,107,46,0.5)',
            }}
          >
            Télécharger l’app →
          </a>
        </div>

        <div className="junto-part-art" style={{ display: 'flex', justifyContent: 'center' }}>
          <ActivityCard />
        </div>
      </div>
    </section>
  );
}
