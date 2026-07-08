import type { CSSProperties } from 'react';
import { INK, ORANGE, PAPER } from './shared';
import { TEARDROP } from './map-pins';

function FooterMark({ size = 30 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 54 54" aria-hidden>
      <path d={TEARDROP} fill={ORANGE} stroke={PAPER} strokeWidth="2" />
      <circle cx="27" cy="24" r="13" fill={PAPER} />
    </svg>
  );
}

const linkStyle: CSSProperties = {
  color: PAPER,
  opacity: 0.75,
  textDecoration: 'none',
};

export default function Footer() {
  return (
    <footer
      className="junto-footer"
      style={{
        padding: '56px 40px 40px',
        background: INK,
        color: PAPER,
        borderTop: `3px solid ${ORANGE}`,
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
          <div style={{ display: 'flex', alignItems: 'center', gap: 11, marginBottom: 16 }}>
            <FooterMark />
            <span className="display" style={{ fontSize: 21, fontWeight: 800, letterSpacing: '-0.02em' }}>
              Junto
            </span>
          </div>
          <a
            href="mailto:contact@getjunto.app"
            style={{
              fontSize: 14,
              color: ORANGE,
              fontWeight: 600,
              textDecoration: 'none',
              borderBottom: `1px solid ${ORANGE}55`,
              paddingBottom: 2,
            }}
          >
            contact@getjunto.app
          </a>
        </div>

        <div style={{ display: 'flex', gap: 48, fontSize: 14, flexWrap: 'wrap' }}>
          <div>
            <div className="mono" style={{ fontSize: 11, opacity: 0.45, letterSpacing: '0.15em', marginBottom: 14 }}>
              PRODUIT
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
              <a href="#comment" style={linkStyle}>Communauté</a>
              <a href="#pro" style={linkStyle}>Pros</a>
              <a href="#sorties" style={linkStyle}>Sorties</a>
              <a href="#beta" style={linkStyle}>Télécharger</a>
            </div>
          </div>
          <div>
            <div className="mono" style={{ fontSize: 11, opacity: 0.45, letterSpacing: '0.15em', marginBottom: 14 }}>
              LÉGAL
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
              <a href="/legal/privacy" style={linkStyle}>Confidentialité</a>
              <a href="/legal/terms" style={linkStyle}>Conditions</a>
              <a href="/legal/mentions" style={linkStyle}>Mentions légales</a>
              <a href="/legal/account-deletion" style={linkStyle}>Suppression de compte</a>
            </div>
          </div>
        </div>
      </div>

      <div
        style={{
          maxWidth: 1180,
          margin: '48px auto 0',
          borderTop: `1px solid ${PAPER}22`,
          paddingTop: 24,
          display: 'flex',
          justifyContent: 'space-between',
          gap: 16,
          flexWrap: 'wrap',
          fontSize: 12,
          opacity: 0.55,
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
