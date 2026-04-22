import {
  CREAM,
  JuntoMark,
  MINT,
  NAVY,
  NAVY_DEEP,
  ORANGE,
  ORANGE_SOFT,
  Pin,
  SKY,
} from './shared';

function HeroMountains() {
  return (
    <svg
      viewBox="0 0 1400 700"
      preserveAspectRatio="xMidYMid slice"
      style={{ width: '100%', height: '100%', display: 'block' }}
      aria-hidden
    >
      <defs>
        <linearGradient id="skyGrad" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#2A4268" />
          <stop offset="55%" stopColor={NAVY} />
          <stop offset="100%" stopColor={NAVY_DEEP} />
        </linearGradient>
        <radialGradient id="sunGlow" cx="0.5" cy="0.5" r="0.5">
          <stop offset="0%" stopColor={ORANGE_SOFT} stopOpacity="0.55" />
          <stop offset="55%" stopColor={ORANGE_SOFT} stopOpacity="0.12" />
          <stop offset="100%" stopColor={ORANGE_SOFT} stopOpacity="0" />
        </radialGradient>
      </defs>

      <rect width="1400" height="700" fill="url(#skyGrad)" />

      <circle cx="1100" cy="180" r="280" fill="url(#sunGlow)" />
      <circle cx="1100" cy="180" r="72" fill={CREAM} opacity="0.92" />

      {(
        [
          [120, 80],
          [240, 140],
          [380, 60],
          [520, 110],
          [660, 50],
          [60, 180],
          [180, 230],
          [340, 200],
          [820, 90],
          [940, 150],
          [1280, 260],
        ] as const
      ).map(([x, y], i) => (
        <circle key={i} cx={x} cy={y} r={1.6} fill={CREAM} opacity={0.7} />
      ))}

      {/* Topo contours in the sky area */}
      <g opacity="0.12" stroke={CREAM} strokeWidth="1" fill="none">
        <path d="M 0 200 Q 400 160 800 220 T 1400 200" />
        <path d="M 0 150 Q 400 110 800 170 T 1400 150" />
        <path d="M 0 100 Q 400 60 800 120 T 1400 100" />
      </g>

      {/* Distant mountains */}
      <path
        d="M 0 420 Q 120 340 240 370 Q 380 400 500 350 Q 640 290 780 340 Q 920 380 1080 330 Q 1240 280 1400 340 L 1400 700 L 0 700 Z"
        fill={NAVY_DEEP}
        opacity="0.75"
      />

      {/* Mid mountains */}
      <path
        d="M 0 500 Q 140 420 290 450 Q 440 480 580 440 Q 740 390 880 430 Q 1040 470 1200 430 Q 1320 400 1400 440 L 1400 700 L 0 700 Z"
        fill="#0B1728"
      />

      {/* Front hills */}
      <path
        d="M 0 570 Q 180 510 360 540 Q 540 570 720 530 Q 900 490 1080 530 Q 1240 565 1400 530 L 1400 700 L 0 700 Z"
        fill="#071221"
      />

      {/* Winding dashed paths */}
      <path
        d="M 200 690 Q 360 620 500 580 Q 620 548 700 460 Q 760 392 840 330"
        fill="none"
        stroke={ORANGE}
        strokeWidth="3.5"
        strokeDasharray="2 8"
        strokeLinecap="round"
        opacity="0.85"
      />
      <path
        d="M 900 690 Q 1040 620 1140 550 Q 1230 488 1280 400"
        fill="none"
        stroke={CREAM}
        strokeWidth="2.5"
        strokeDasharray="2 6"
        strokeLinecap="round"
        opacity="0.5"
      />

      {/* Pins */}
      <Pin x={500} y={580} color={ORANGE} emoji="🧗" />
      <Pin x={700} y={460} color={MINT} emoji="🥾" />
      <Pin x={840} y={330} color={SKY} emoji="🪂" />
      <Pin x={1140} y={550} color={CREAM} emoji="🚵" dark />
    </svg>
  );
}

export default function Hero() {
  const headline = { line1: 'Trouve, crée,', line2: 'rejoins.' };

  return (
    <section
      style={{
        position: 'relative',
        minHeight: 760,
        background: NAVY,
        color: '#FFF',
        overflow: 'hidden',
      }}
    >
      <nav
        style={{
          position: 'relative',
          zIndex: 10,
          maxWidth: 1280,
          margin: '0 auto',
          padding: '28px 40px',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          gap: 16,
          flexWrap: 'wrap',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <JuntoMark size={40} />
          <span className="display" style={{ fontSize: 24, fontWeight: 800, letterSpacing: '-0.02em' }}>
            Junto
          </span>
        </div>
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 28,
            fontSize: 15,
            fontWeight: 500,
            flexWrap: 'wrap',
          }}
        >
          <a href="#comment" style={{ textDecoration: 'none', opacity: 0.85 }}>
            Comment ça marche
          </a>
          <a href="#sorties" style={{ textDecoration: 'none', opacity: 0.85 }}>
            Sorties
          </a>
          <a
            href="#beta"
            style={{
              background: '#FFF',
              color: NAVY,
              padding: '10px 18px',
              borderRadius: 999,
              textDecoration: 'none',
              fontWeight: 700,
            }}
          >
            Rejoindre la bêta
          </a>
        </div>
      </nav>

      <div style={{ position: 'absolute', inset: 0, zIndex: 0 }}>
        <HeroMountains />
        <div
          style={{
            position: 'absolute',
            inset: 0,
            background: `linear-gradient(90deg, ${NAVY} 0%, ${NAVY} 25%, rgba(30,47,77,0.7) 45%, rgba(30,47,77,0) 70%)`,
          }}
        />
      </div>

      <div
        style={{
          position: 'relative',
          zIndex: 5,
          maxWidth: 1280,
          margin: '0 auto',
          padding: '70px 40px 140px',
          display: 'grid',
          gridTemplateColumns: 'minmax(0, 1.15fr) minmax(0, 1fr)',
          gap: 40,
          alignItems: 'center',
          minHeight: 560,
        }}
      >
        <div>
          <h1
            className="display"
            style={{
              fontSize: 'clamp(48px, 8vw, 88px)',
              lineHeight: 0.95,
              margin: 0,
              fontWeight: 800,
              letterSpacing: '-0.035em',
              textWrap: 'balance',
              textTransform: 'none',
            }}
          >
            {headline.line1}
            <br />
            <span style={{ color: ORANGE_SOFT }}>{headline.line2}</span>
          </h1>

          <p
            style={{
              fontSize: 19,
              lineHeight: 1.5,
              maxWidth: 460,
              margin: '32px 0 44px',
              opacity: 0.82,
            }}
          >
            Trouve, crée, organise tes sorties outdoor. Près de chez toi.
          </p>

          <div style={{ display: 'flex', alignItems: 'center', gap: 24, flexWrap: 'wrap' }}>
            <a
              href="#beta"
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: 10,
                background: ORANGE,
                color: '#FFF',
                padding: '18px 28px',
                borderRadius: 12,
                fontSize: 16,
                fontWeight: 700,
                textDecoration: 'none',
                boxShadow: '0 10px 30px -8px rgba(242,107,46,0.5)',
              }}
            >
              Rejoindre la bêta
              <svg
                width="18"
                height="18"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2.5"
                strokeLinecap="round"
              >
                <path d="M5 12h14M13 5l7 7-7 7" />
              </svg>
            </a>
            <div
              className="mono"
              style={{ fontSize: 12, opacity: 0.6, letterSpacing: '0.08em' }}
            >
              ANDROID · APK DIRECT
            </div>
          </div>
        </div>

        <div />
      </div>
    </section>
  );
}
