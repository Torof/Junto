// Hero v2 — built from the app's own materials (validated on the mock):
// light paper palette from the app theme, brutalist CTA, a REAL Mapbox
// outdoors fragment (the Écrins / Vallouise valley, committed as a static
// asset — no runtime token needed) carrying the exact pin system: UA stone
// teardrops + sport emoji, RA with its PRO capsule, PP pushpin on a village.
// Copy: validated 2026-07-07 (« aventure » disambiguates « sortie » for the
// public façade; « entre passionnés » replaces « particuliers »).
// The slogan slot is a PLACEHOLDER — Scott is workshopping the real one.

import { UaPin, RaPin, PpPin, TEARDROP, PRO_BLUE } from './map-pins';

const PAPER = '#F5EEDF';
const INK = '#1F1A15';
const INK_SOFT = '#4A4034';
const CTA_ORANGE = '#F26B2E';
const STONE = '#E0D2B4';

function JuntoTeardropMark({ size = 34 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 54 54" aria-hidden>
      <path d={TEARDROP} fill={CTA_ORANGE} stroke={INK} strokeWidth="3" />
      <circle cx="27" cy="24" r="13" fill={PAPER} stroke={INK} strokeWidth="2.4" />
    </svg>
  );
}

export default function Hero() {
  return (
    <section
      className="junto-hero"
      style={{
        position: 'relative',
        background: PAPER,
        color: INK,
        overflow: 'hidden',
        borderBottom: `2px solid ${INK}`,
      }}
    >
      <nav
        className="junto-hero-nav"
        style={{
          position: 'relative',
          zIndex: 10,
          maxWidth: 1280,
          margin: '0 auto',
          padding: '26px 40px',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          gap: 16,
          flexWrap: 'wrap',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 11 }}>
          <JuntoTeardropMark />
          <span className="display" style={{ fontSize: 23, fontWeight: 800, letterSpacing: '-0.02em' }}>
            Junto
          </span>
        </div>
        <div
          className="junto-hero-nav-links"
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 26,
            fontSize: 15,
            fontWeight: 600,
            flexWrap: 'wrap',
          }}
        >
          <a className="junto-hero-nav-link" href="#comment" style={{ textDecoration: 'none', color: INK, opacity: 0.78 }}>
            Communauté
          </a>
          <a className="junto-hero-nav-link" href="#pro" style={{ textDecoration: 'none', color: INK, opacity: 0.78 }}>
            Pros
          </a>
          <a
            className="junto-hero-nav-cta"
            href="#beta"
            style={{
              background: INK,
              color: PAPER,
              padding: '10px 18px',
              borderRadius: 999,
              textDecoration: 'none',
              fontWeight: 700,
            }}
          >
            Télécharger l'app
          </a>
        </div>
      </nav>

      <div
        className="junto-hero-grid"
        style={{
          position: 'relative',
          zIndex: 5,
          maxWidth: 1280,
          margin: '0 auto',
          padding: '40px 40px 90px',
          display: 'grid',
          gridTemplateColumns: 'minmax(0, 1.02fr) minmax(0, 1fr)',
          gap: 40,
          alignItems: 'center',
        }}
      >
        <div>
          {/* The slogan IS the headline — the peer-to-peer line people say to
              each other (Point S-style). Two staggered lines: the second steps
              to the right and turns orange for a spoken, punchy cadence. */}
          <h1 className="display junto-hero-title" style={{ margin: 0 }}>
            <span
              style={{
                display: 'block',
                fontSize: 'clamp(38px, 5.6vw, 68px)',
                lineHeight: 1.02,
                fontWeight: 900,
                letterSpacing: '-0.035em',
                textWrap: 'balance',
              }}
            >
              Marre du sport solo&nbsp;?
            </span>
            <span
              style={{
                display: 'block',
                marginTop: 2,
                marginLeft: '1.4em',
                fontSize: 'clamp(40px, 6vw, 72px)',
                lineHeight: 1.0,
                fontWeight: 900,
                letterSpacing: '-0.04em',
                color: CTA_ORANGE,
              }}
            >
              Va sur Junto.
            </span>
          </h1>

          <p
            style={{
              fontSize: 'clamp(19px, 2.6vw, 25px)',
              lineHeight: 1.25,
              fontWeight: 700,
              maxWidth: 460,
              margin: '24px 0 0',
              color: INK,
              textWrap: 'balance',
            }}
          >
            Ta prochaine aventure est déjà sur la carte.
          </p>

          <p
            className="junto-hero-lead"
            style={{
              fontSize: 17,
              lineHeight: 1.55,
              maxWidth: 460,
              margin: '14px 0 38px',
              color: INK_SOFT,
            }}
          >
            Jamais à court de sorties, ni de monde pour les partager.{' '}
            <strong style={{ color: INK }}>Entre passionnés</strong> ou{' '}
            <strong style={{ color: INK }}>encadré par un pro</strong>.
          </p>

          <div style={{ display: 'flex', alignItems: 'center', gap: 24, flexWrap: 'wrap' }}>
            <a
              className="junto-hero-cta"
              href="#beta"
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: 10,
                background: CTA_ORANGE,
                color: '#FFF',
                padding: '17px 28px',
                borderRadius: 14,
                border: `2px solid ${INK}`,
                fontSize: 16,
                fontWeight: 800,
                textDecoration: 'none',
                boxShadow: `4px 4px 0 ${INK}`,
              }}
            >
              Télécharger l'app
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
                <path d="M5 12h14M13 5l7 7-7 7" />
              </svg>
            </a>
            <div className="mono" style={{ fontSize: 12, color: INK_SOFT, letterSpacing: '0.08em' }}>
              ANDROID · APK DIRECT
            </div>
          </div>
        </div>

        {/* The map IS the hero: real Écrins fragment + the three pin species. */}
        <div
          className="junto-hero-map"
          role="img"
          aria-label="Fragment de carte Junto avec des sorties épinglées dans les Écrins"
          style={{
            position: 'relative',
            border: `2px solid ${INK}`,
            borderRadius: 18,
            overflow: 'hidden',
            boxShadow: `6px 6px 0 ${STONE}`,
            aspectRatio: '10 / 11',
            maxHeight: 560,
          }}
        >
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src="/hero-map-ecrins.jpg"
            alt=""
            style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover' }}
          />

          <div className="junto-hero-pin" style={{ left: '12%', top: '68%', width: 44 }}>
            <UaPin emoji="🧗" />
          </div>
          <div className="junto-hero-pin" style={{ left: '58%', top: '70%', width: 44 }}>
            <UaPin emoji="🥾" />
          </div>
          <div className="junto-hero-pin" style={{ left: '44%', top: '36%', width: 44 }}>
            <UaPin emoji="⛷️" />
          </div>
          <div className="junto-hero-pin" style={{ left: '70%', top: '16%', width: 48 }}>
            <RaPin emoji="🪂" />
          </div>
          <div className="junto-hero-pin" style={{ left: '81%', top: '27%', width: 40 }}>
            <PpPin />
          </div>

          <div
            style={{
              position: 'absolute',
              left: 12,
              bottom: 12,
              display: 'flex',
              gap: 8,
              flexWrap: 'wrap',
            }}
            aria-hidden
          >
            <span className="junto-hero-chip">
              <span className="junto-hero-chip-dot" style={{ background: STONE }} />
              Entre passionnés
            </span>
            <span className="junto-hero-chip">
              <span className="junto-hero-chip-dot" style={{ background: PRO_BLUE }} />
              Encadré par un pro
            </span>
          </div>
        </div>
      </div>
    </section>
  );
}
