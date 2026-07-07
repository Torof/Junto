// Hero v2 — built from the app's own materials (validated on the mock):
// light paper palette from the app theme, brutalist CTA, a REAL Mapbox
// outdoors fragment (the Écrins / Vallouise valley, committed as a static
// asset — no runtime token needed) carrying the exact pin system: UA stone
// teardrops + sport emoji, RA with its PRO capsule, PP pushpin on a village.
// Copy: validated 2026-07-07 (« aventure » disambiguates « sortie » for the
// public façade; « entre passionnés » replaces « particuliers »).
// The slogan slot is a PLACEHOLDER — Scott is workshopping the real one.

const PAPER = '#F5EEDF';
const INK = '#1F1A15';
const INK_SOFT = '#4A4034';
const CTA_ORANGE = '#F26B2E';
const STONE = '#E0D2B4';
const PRO_FRAME = '#BFCFE0';
const PRO_BLUE = '#3b82f6';

// Exact app pin geometry (activity-pin.tsx / pro-offering-pin.tsx / pro-pin.tsx).
const TEARDROP =
  'M 27 2 C 13 2 4 12 4 25 C 4 36 21 50 27 52 C 33 50 50 36 50 25 C 50 12 41 2 27 2 Z';

function UaPin({ emoji }: { emoji: string }) {
  return (
    <>
      <svg width="44" height="44" viewBox="0 0 54 54">
        <path d={TEARDROP} fill={STONE} stroke={INK} strokeWidth="2" strokeOpacity=".55" strokeLinejoin="round" />
        <circle cx="27" cy="24" r="18.5" fill="#FFFFFF" stroke={INK} strokeWidth="1.5" strokeOpacity=".95" />
      </svg>
      <span className="junto-hero-pin-emoji">{emoji}</span>
    </>
  );
}

function RaPin({ emoji }: { emoji: string }) {
  return (
    <>
      <svg width="48" height="45" viewBox="0 0 58 54">
        <g transform="translate(4 0)">
          <path d={TEARDROP} fill={PRO_FRAME} stroke={INK} strokeWidth="2" strokeOpacity=".55" strokeLinejoin="round" />
          <circle cx="27" cy="24" r="18.5" fill="#FFFFFF" stroke={INK} strokeWidth="1.5" strokeOpacity=".95" />
        </g>
        <rect x="1" y="1.5" width="22" height="12" rx="6" fill={PRO_BLUE} stroke={INK} strokeWidth="1.3" />
        <text x="12" y="10.6" fontSize="8" fontWeight="bold" letterSpacing=".5" fill="#FFFFFF" textAnchor="middle" fontFamily="system-ui, sans-serif">
          PRO
        </text>
      </svg>
      <span className="junto-hero-pin-emoji" style={{ left: 4 }}>{emoji}</span>
    </>
  );
}

function PpPin() {
  return (
    <svg width="40" height="52" viewBox="0 0 54 70">
      <path d="M 24.6 41 L 27 67 L 29.4 41 Z" fill={INK} />
      <circle cx="27" cy="23" r="21" fill="#FFFFFF" stroke="#6B7280" strokeWidth="1.3" />
      <circle cx="27" cy="23" r="18.5" fill="#4A7C59" />
      <g transform="translate(27 23) scale(0.8) translate(-27 -23)">
        <path d="M 15 32 L 23 16 L 28 23 L 32 18 L 39 32 Z" fill="#F5F5F0" />
      </g>
    </svg>
  );
}

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
          {/* Slogan placeholder — the real one is being workshopped. */}
          <span className="junto-hero-slogan" style={{ fontSize: 13, fontStyle: 'italic', opacity: 0.45, marginLeft: 6 }}>
            « slogan slogan »
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
          <h1
            className="display junto-hero-title"
            style={{
              fontSize: 'clamp(44px, 6.2vw, 76px)',
              lineHeight: 1.0,
              margin: 0,
              fontWeight: 900,
              letterSpacing: '-0.035em',
              textWrap: 'balance',
              textTransform: 'none',
            }}
          >
            Ta prochaine aventure est déjà{' '}
            <span style={{ color: CTA_ORANGE }}>sur la carte.</span>
          </h1>

          <p
            className="junto-hero-lead"
            style={{
              fontSize: 19,
              lineHeight: 1.55,
              maxWidth: 480,
              margin: '28px 0 40px',
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
