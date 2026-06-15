import { CREAM, NAVY, TopoLines } from './shared';

// Pro layer of Junto on the landing (added 2026-06-11 — the storefront /
// offerings / reviews surface, ~a third of the app, was unmentioned).
// Wears the app's pro-pin blue (#3b82f6) so the web identity matches
// what users see on the map. Consumer-first framing (find verified
// pros) closing on a soft pro-recruitment CTA.

const PRO_BLUE = '#3b82f6';
const PRO_BLUE_SOFT = '#7CA6E8';

const FEATURES: { icon: string; title: string; body: string }[] = [
  {
    icon: '✓',
    title: 'Une vitrine vérifiée',
    body: 'Guides diplômés, écoles, moniteurs — vérifiés par Junto. Pas de faux pros.',
  },
  {
    icon: '📍',
    title: 'Leur catalogue sur la carte',
    body: 'Chaque prestation est une punaise bleue, posée là où elle se passe vraiment.',
  },
  {
    icon: '★',
    title: 'Les avis, en transparence',
    body: 'Note, commente, le pro répond. Comme sur une carte que tu connais déjà.',
  },
];

function StorefrontCard() {
  return (
    <div
      className="junto-pro-card"
      style={{
        background: '#FFF',
        borderRadius: 24,
        padding: 28,
        boxShadow: '0 30px 60px -20px rgba(30,47,77,0.35)',
        border: '1px solid var(--line)',
        maxWidth: 380,
        width: '100%',
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 16, marginBottom: 18 }}>
        <div
          style={{
            width: 64,
            height: 64,
            borderRadius: '50%',
            background: `linear-gradient(135deg, ${PRO_BLUE} 0%, ${PRO_BLUE_SOFT} 100%)`,
            border: `3px solid ${PRO_BLUE}`,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            fontSize: 30,
            flexShrink: 0,
          }}
        >
          🏔️
        </div>
        <div style={{ minWidth: 0 }}>
          <div
            className="mono"
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: 5,
              fontSize: 9,
              fontWeight: 700,
              color: PRO_BLUE,
              background: PRO_BLUE + '18',
              padding: '3px 8px',
              borderRadius: 999,
              letterSpacing: '0.1em',
              marginBottom: 6,
            }}
          >
            ✓ PAGE PRO VÉRIFIÉE
          </div>
          <div
            className="display"
            style={{ fontSize: 19, fontWeight: 800, color: NAVY, letterSpacing: '-0.02em', lineHeight: 1.1 }}
          >
            Cédric — Guide de haute montagne
          </div>
        </div>
      </div>

      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 18 }}>
        <span style={{ color: PRO_BLUE, fontSize: 15, letterSpacing: 1 }}>★★★★★</span>
        <span style={{ fontSize: 13, fontWeight: 700, color: NAVY }}>4,9</span>
        <span style={{ fontSize: 13, color: 'var(--muted)' }}>· 23 avis</span>
      </div>

      <div style={{ height: 1, background: 'var(--line)', margin: '0 0 16px' }} />

      <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
        {[
          ['Couloir Nord des Écrins', 'Alpinisme · 1 jour'],
          ['Arête des Trois Becs', 'Course rocheuse · AD'],
          ['Cascade de glace', 'Initiation · matériel fourni'],
        ].map(([title, sub]) => (
          <div key={title} style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <span
              style={{
                width: 22,
                height: 22,
                borderRadius: 6,
                background: PRO_BLUE + '18',
                color: PRO_BLUE,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontSize: 11,
                flexShrink: 0,
              }}
            >
              📍
            </span>
            <div style={{ minWidth: 0 }}>
              <div style={{ fontSize: 14, fontWeight: 700, color: NAVY, lineHeight: 1.2 }}>{title}</div>
              <div className="mono" style={{ fontSize: 10, color: 'var(--muted)', letterSpacing: '0.04em' }}>
                {sub}
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

export default function Pro() {
  return (
    <section
      id="pro"
      className="junto-pro"
      style={{
        padding: '140px 40px',
        background: NAVY,
        position: 'relative',
        overflow: 'hidden',
      }}
    >
      <TopoLines opacity={0.05} color={CREAM} count={10} />
      <div
        className="junto-pro-grid"
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
            className="display junto-pro-title"
            style={{
              fontSize: 'clamp(44px, 6.5vw, 68px)',
              lineHeight: 0.98,
              margin: '0 0 16px',
              fontWeight: 800,
              letterSpacing: '-0.035em',
              color: PRO_BLUE_SOFT,
              textWrap: 'balance',
            }}
          >
            Avec des pros
          </h2>
          <p
            style={{
              fontSize: 19,
              lineHeight: 1.5,
              margin: '0 0 40px',
              color: '#FFF',
              fontWeight: 500,
              maxWidth: 520,
            }}
          >
            Guides diplômés, écoles, moniteurs — vérifiés, avec leur catalogue de prestations posé
            directement sur la carte.
          </p>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 22, marginBottom: 36 }}>
            {FEATURES.map((f) => (
              <div key={f.title} style={{ display: 'flex', gap: 16 }}>
                <span
                  style={{
                    width: 34,
                    height: 34,
                    borderRadius: 10,
                    background: PRO_BLUE + '33',
                    color: PRO_BLUE_SOFT,
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    fontSize: 15,
                    fontWeight: 700,
                    flexShrink: 0,
                  }}
                >
                  {f.icon}
                </span>
                <div>
                  <div
                    className="display"
                    style={{ fontSize: 19, fontWeight: 800, color: '#FFF', letterSpacing: '-0.015em', marginBottom: 3 }}
                  >
                    {f.title}
                  </div>
                  <div style={{ fontSize: 15, lineHeight: 1.5, color: 'rgba(245,245,240,0.62)', maxWidth: 460 }}>
                    {f.body}
                  </div>
                </div>
              </div>
            ))}
          </div>

          <p
            style={{
              fontSize: 13,
              lineHeight: 1.5,
              color: 'rgba(245,245,240,0.5)',
              fontStyle: 'italic',
              margin: '0 0 28px',
              maxWidth: 480,
            }}
          >
            Junto est la vitrine et la carte. La réservation et le paiement se font en direct avec le
            pro — Junto ne prend pas de commission.
          </p>

          <a
            href="mailto:contact@getjunto.app?subject=Cr%C3%A9er%20ma%20page%20pro%20sur%20Junto"
            className="junto-pro-cta"
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: 10,
              background: PRO_BLUE,
              color: '#FFF',
              padding: '15px 26px',
              borderRadius: 12,
              fontSize: 15,
              fontWeight: 700,
              textDecoration: 'none',
              boxShadow: '0 10px 30px -8px rgba(59,130,246,0.5)',
            }}
          >
            Tu encadres des sorties ? Crée ta page pro →
          </a>
        </div>

        <div className="junto-pro-art" style={{ display: 'flex', justifyContent: 'center' }}>
          <StorefrontCard />
        </div>
      </div>
    </section>
  );
}
