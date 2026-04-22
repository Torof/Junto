import { JuntoMark, NAVY_DEEP, ORANGE_SOFT } from './shared';

export default function Footer() {
  return (
    <footer
      className="junto-footer"
      style={{
        padding: '56px 40px 40px',
        background: NAVY_DEEP,
        color: '#FFF',
        borderTop: '1px solid rgba(255,255,255,0.06)',
      }}
    >
      <div
        style={{
          maxWidth: 1180,
          margin: '0 auto',
          display: 'flex',
          alignItems: 'flex-start',
          justifyContent: 'space-between',
          gap: 40,
          flexWrap: 'wrap',
        }}
      >
        <div style={{ maxWidth: 320 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 16 }}>
            <JuntoMark size={32} />
            <span
              className="display"
              style={{ fontSize: 20, fontWeight: 800, letterSpacing: '-0.02em' }}
            >
              Junto
            </span>
          </div>
          <a
            href="mailto:contact@getjunto.app"
            style={{
              fontSize: 14,
              color: ORANGE_SOFT,
              textDecoration: 'none',
              borderBottom: `1px solid ${ORANGE_SOFT}44`,
              paddingBottom: 2,
            }}
          >
            contact@getjunto.app
          </a>
        </div>

        <div style={{ display: 'flex', gap: 48, fontSize: 14, flexWrap: 'wrap' }}>
          <div>
            <div
              className="mono"
              style={{
                fontSize: 11,
                opacity: 0.4,
                letterSpacing: '0.15em',
                marginBottom: 14,
              }}
            >
              PRODUIT
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
              <a href="#comment" style={{ opacity: 0.8, textDecoration: 'none' }}>
                Comment ça marche
              </a>
              <a href="#sorties" style={{ opacity: 0.8, textDecoration: 'none' }}>
                Sorties
              </a>
              <a href="#beta" style={{ opacity: 0.8, textDecoration: 'none' }}>
                Bêta
              </a>
            </div>
          </div>
          <div>
            <div
              className="mono"
              style={{
                fontSize: 11,
                opacity: 0.4,
                letterSpacing: '0.15em',
                marginBottom: 14,
              }}
            >
              LÉGAL
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
              <a href="/legal/privacy" style={{ opacity: 0.8, textDecoration: 'none' }}>
                Confidentialité
              </a>
              <a href="/legal/terms" style={{ opacity: 0.8, textDecoration: 'none' }}>
                Conditions
              </a>
            </div>
          </div>
        </div>
      </div>

      <div
        style={{
          maxWidth: 1180,
          margin: '48px auto 0',
          borderTop: '1px solid rgba(255,255,255,0.08)',
          paddingTop: 24,
          display: 'flex',
          justifyContent: 'space-between',
          gap: 16,
          flexWrap: 'wrap',
          fontSize: 12,
          opacity: 0.45,
        }}
      >
        <div>© Junto 2026</div>
        <div className="mono" style={{ letterSpacing: '0.1em' }}>
          MADE IN FRANCE 🏔️
        </div>
      </div>
    </footer>
  );
}
