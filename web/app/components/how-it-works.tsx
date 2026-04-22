import { CREAM, NAVY, NAVY_DEEP, ORANGE, ORANGE_SOFT, SectionLabel } from './shared';

const STEPS = [
  { n: '01', title: 'Trouve', body: 'Ouvre la carte.' },
  { n: '02', title: 'Rejoins', body: 'Un tap, tu es dedans.' },
  { n: '03', title: 'Pars', body: 'Chat, transport, go.' },
];

const PIN_POSITIONS = [
  { x: '18%', y: '72%', step: STEPS[0] },
  { x: '50%', y: '50%', step: STEPS[1] },
  { x: '82%', y: '28%', step: STEPS[2] },
];

export default function HowItWorks() {
  return (
    <section
      id="comment"
      className="junto-hiw"
      style={{
        padding: '140px 40px',
        background: NAVY,
        color: '#FFF',
        position: 'relative',
        overflow: 'hidden',
      }}
    >
      <div style={{ maxWidth: 1180, margin: '0 auto', position: 'relative' }}>
        <div style={{ marginBottom: 60, maxWidth: 720 }}>
          <SectionLabel color={ORANGE_SOFT}>Comment ça marche</SectionLabel>
          <h2
            className="display junto-hiw-title"
            style={{
              fontSize: 'clamp(40px, 6vw, 64px)',
              lineHeight: 0.98,
              margin: 0,
              fontWeight: 800,
              letterSpacing: '-0.035em',
              textWrap: 'balance',
            }}
          >
            Trois arrêts
            <br />
            <span style={{ color: ORANGE_SOFT }}>sur ton itinéraire.</span>
          </h2>
        </div>

        <div
          className="junto-hiw-map"
          style={{
            position: 'relative',
            borderRadius: 24,
            overflow: 'hidden',
            background: '#132238',
            border: '1px solid rgba(255,255,255,0.08)',
            aspectRatio: '16 / 8',
          }}
        >
          <svg
            viewBox="0 0 1400 700"
            preserveAspectRatio="xMidYMid slice"
            style={{ width: '100%', height: '100%', display: 'block' }}
            aria-hidden
          >
            <defs>
              <pattern id="gridPattern" width="50" height="50" patternUnits="userSpaceOnUse">
                <path d="M 50 0 L 0 0 0 50" fill="none" stroke={CREAM} strokeWidth="0.5" opacity="0.08" />
              </pattern>
            </defs>

            <rect width="1400" height="700" fill="url(#gridPattern)" />

            <g stroke={ORANGE_SOFT} strokeWidth="1" fill="none" opacity="0.25">
              <path d="M 200 600 Q 400 500 600 550 Q 800 600 1000 480 Q 1200 380 1300 420" />
              <path d="M 200 540 Q 400 440 600 490 Q 800 540 1000 420 Q 1200 320 1300 360" />
              <path d="M 200 480 Q 400 380 600 430 Q 800 480 1000 360 Q 1200 260 1300 300" />
              <path d="M 250 420 Q 420 340 600 370 Q 800 420 1000 300 Q 1180 200 1260 240" />
              <path d="M 320 360 Q 460 300 600 310 Q 800 360 1000 240 Q 1160 160 1200 180" />
            </g>

            <g stroke={CREAM} strokeWidth="0.8" fill="none" opacity="0.15">
              <path d="M 60 200 Q 180 140 280 180 Q 380 210 500 170" />
              <path d="M 60 160 Q 180 100 280 140 Q 380 170 500 130" />
              <path d="M 900 140 Q 1040 80 1180 120 Q 1290 150 1370 110" />
            </g>

            <path
              d="M 252 504 C 420 470, 540 420, 700 350 C 860 280, 1000 220, 1148 196"
              fill="none"
              stroke={ORANGE}
              strokeWidth="4"
              strokeLinecap="round"
              strokeDasharray="2 10"
            />

            {/* North arrow */}
            <g transform="translate(80, 60)">
              <path d="M 0 -22 L 8 10 L 0 2 L -8 10 Z" fill={CREAM} opacity="0.6" />
              <text
                x="0"
                y="26"
                textAnchor="middle"
                fontSize="11"
                fill={CREAM}
                opacity="0.6"
                fontFamily="JetBrains Mono, monospace"
                letterSpacing="0.1em"
              >
                N
              </text>
            </g>

            {/* Scale */}
            <g transform="translate(1200, 640)">
              <rect x="0" y="0" width="60" height="4" fill={CREAM} opacity="0.4" />
              <rect x="60" y="0" width="60" height="4" fill="none" stroke={CREAM} strokeWidth="1" opacity="0.4" />
              <text
                x="60"
                y="22"
                textAnchor="middle"
                fontSize="10"
                fill={CREAM}
                opacity="0.5"
                fontFamily="JetBrains Mono, monospace"
                letterSpacing="0.08em"
              >
                1 KM
              </text>
            </g>
          </svg>

          {PIN_POSITIONS.map((p, i) => (
            <div
              key={i}
              style={{
                position: 'absolute',
                left: p.x,
                top: p.y,
                transform: 'translate(-50%, -100%)',
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
              }}
            >
              <div
                style={{
                  background: '#FFF',
                  color: NAVY,
                  padding: '14px 18px',
                  borderRadius: 12,
                  marginBottom: 14,
                  minWidth: 180,
                  textAlign: 'left',
                  boxShadow: '0 20px 40px -10px rgba(0,0,0,0.4)',
                }}
              >
                <div
                  className="mono"
                  style={{
                    fontSize: 10,
                    color: ORANGE,
                    letterSpacing: '0.15em',
                    marginBottom: 4,
                  }}
                >
                  ÉTAPE {p.step.n}
                </div>
                <div
                  className="display"
                  style={{
                    fontSize: 22,
                    fontWeight: 800,
                    letterSpacing: '-0.02em',
                    lineHeight: 1,
                    marginBottom: 4,
                  }}
                >
                  {p.step.title}
                </div>
                <div style={{ fontSize: 13, color: 'var(--muted)', lineHeight: 1.4 }}>
                  {p.step.body}
                </div>
              </div>
              <svg width="44" height="56" viewBox="0 0 44 56">
                <path
                  d="M 22 54 L 13 40 Q 2 40 2 22 Q 2 2 22 2 Q 42 2 42 22 Q 42 40 31 40 Z"
                  fill={ORANGE}
                  stroke={NAVY_DEEP}
                  strokeWidth="2.5"
                />
                <circle cx="22" cy="21" r="9" fill="#FFF" />
                <text
                  x="22"
                  y="25"
                  textAnchor="middle"
                  fontSize="11"
                  fontWeight="800"
                  fill={NAVY}
                  fontFamily="Archivo, sans-serif"
                >
                  {i + 1}
                </text>
              </svg>
            </div>
          ))}
        </div>

        <div className="junto-hiw-steps-mobile">
          {STEPS.map((step, i) => (
            <div key={i} className="junto-hiw-step-card">
              <div className="junto-hiw-step-pin">
                <svg width="44" height="56" viewBox="0 0 44 56">
                  <path
                    d="M 22 54 L 13 40 Q 2 40 2 22 Q 2 2 22 2 Q 42 2 42 22 Q 42 40 31 40 Z"
                    fill={ORANGE}
                    stroke={NAVY_DEEP}
                    strokeWidth="2.5"
                  />
                  <circle cx="22" cy="21" r="9" fill="#FFF" />
                  <text
                    x="22"
                    y="25"
                    textAnchor="middle"
                    fontSize="11"
                    fontWeight="800"
                    fill={NAVY}
                    fontFamily="Archivo, sans-serif"
                  >
                    {i + 1}
                  </text>
                </svg>
              </div>
              <div className="junto-hiw-step-body">
                <div
                  className="mono"
                  style={{
                    fontSize: 10,
                    color: ORANGE,
                    letterSpacing: '0.15em',
                    marginBottom: 4,
                  }}
                >
                  ÉTAPE {step.n}
                </div>
                <div
                  className="display"
                  style={{
                    fontSize: 22,
                    fontWeight: 800,
                    letterSpacing: '-0.02em',
                    lineHeight: 1,
                    marginBottom: 6,
                    color: '#FFF',
                  }}
                >
                  {step.title}
                </div>
                <div style={{ fontSize: 14, color: 'rgba(255,255,255,0.7)', lineHeight: 1.4 }}>
                  {step.body}
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
