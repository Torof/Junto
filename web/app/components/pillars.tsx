import { NAVY, ORANGE, SectionLabel, TopoLines } from './shared';

type ArtKind = 'map' | 'create' | 'organize';

const ITEMS: { kicker: string; title: string; body: string; art: ArtKind }[] = [
  {
    kicker: 'Trouve',
    title: 'Une carte vivante des sorties autour de toi.',
    body: "Filtre par sport, date, niveau. Vois en un coup d'œil qui part où, quand.",
    art: 'map',
  },
  {
    kicker: 'Crée',
    title: 'Lance ta propre sortie en 30 secondes.',
    body: 'Fixe le RDV, le matos, le niveau. Ta sortie apparaît sur la carte, les autres rejoignent.',
    art: 'create',
  },
  {
    kicker: 'Organise',
    title: 'Covoiturage, chat, matos — tout au même endroit.',
    body: "Plus de groupes WhatsApp à 40. Les infos de la sortie vivent dans la sortie.",
    art: 'organize',
  },
];

function PillarArt({ kind }: { kind: ArtKind }) {
  if (kind === 'map') {
    return (
      <svg viewBox="0 0 320 220" style={{ width: '100%', height: '100%' }} preserveAspectRatio="xMidYMid slice">
        <defs>
          <pattern id="pMapGrid" width="32" height="32" patternUnits="userSpaceOnUse">
            <path d="M 32 0 L 0 0 0 32" fill="none" stroke="#FFF" strokeWidth="0.4" opacity="0.3" />
          </pattern>
        </defs>
        <rect width="320" height="220" fill="#EFE4CE" />
        <path
          d="M -10 -10 Q 60 20 90 60 Q 70 110 120 140 Q 90 180 40 200 L -10 220 Z"
          fill="#C9D9B8"
          opacity="0.8"
        />
        <path
          d="M 220 -10 Q 260 30 250 70 Q 290 100 310 80 L 330 -10 Z"
          fill="#C9D9B8"
          opacity="0.8"
        />
        <path
          d="M 180 180 Q 230 170 260 200 L 280 230 L 180 230 Z"
          fill="#C9D9B8"
          opacity="0.8"
        />
        <path
          d="M -10 110 Q 80 90 140 120 Q 200 150 320 130 L 320 150 Q 200 170 140 140 Q 80 110 -10 130 Z"
          fill="#B8D1E3"
        />
        <path
          d="M -10 110 Q 80 90 140 120 Q 200 150 320 130"
          fill="none"
          stroke="#8FB3CC"
          strokeWidth="0.6"
          opacity="0.6"
        />
        <ellipse cx="70" cy="180" rx="24" ry="14" fill="#B8D1E3" />
        <g fill="none" strokeLinecap="round">
          <path d="M 0 70 Q 100 50 180 80 T 320 60" stroke="#FFF" strokeWidth="3" />
          <path d="M 0 70 Q 100 50 180 80 T 320 60" stroke="#E8A66B" strokeWidth="1.5" />
          <path d="M 40 0 Q 80 80 150 110 Q 200 140 240 220" stroke="#FFF" strokeWidth="2.5" />
          <path d="M 40 0 Q 80 80 150 110 Q 200 140 240 220" stroke="#D9CDB4" strokeWidth="1" />
        </g>
        <rect width="320" height="220" fill="url(#pMapGrid)" opacity="0.4" />
        {(
          [
            [70, 75, ORANGE, '🧗'],
            [210, 55, NAVY, '🥾'],
            [250, 130, ORANGE, '🪂'],
            [140, 170, NAVY, '🚵'],
          ] as const
        ).map(([x, y, c, e], i) => (
          <g key={i} transform={`translate(${x - 14}, ${y - 32})`}>
            <ellipse cx="14" cy="34" rx="8" ry="2" fill="#000" opacity="0.18" />
            <path
              d="M 14 32 L 8 22 Q 0 22 0 12 Q 0 0 14 0 Q 28 0 28 12 Q 28 22 20 22 Z"
              fill={c}
              stroke="#FFF"
              strokeWidth="1.5"
            />
            <text x="14" y="16" textAnchor="middle" fontSize="12" dominantBaseline="middle">
              {e}
            </text>
          </g>
        ))}
        <g transform="translate(40, 140)">
          <circle r="14" fill={ORANGE} opacity="0.2" />
          <circle r="7" fill={ORANGE} opacity="0.35" />
          <circle r="4" fill={ORANGE} stroke="#FFF" strokeWidth="1.5" />
        </g>
      </svg>
    );
  }

  if (kind === 'create') {
    return (
      <div
        style={{
          position: 'absolute',
          inset: 0,
          padding: 20,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        <div
          style={{
            background: '#FFF',
            borderRadius: 14,
            padding: 18,
            width: 260,
            boxShadow: '0 20px 40px -10px rgba(0,0,0,0.3)',
          }}
        >
          <div
            className="mono"
            style={{ fontSize: 10, color: ORANGE, letterSpacing: '0.12em', marginBottom: 8 }}
          >
            NOUVELLE SORTIE
          </div>
          <div
            className="display"
            style={{
              fontSize: 18,
              fontWeight: 800,
              color: NAVY,
              letterSpacing: '-0.02em',
              marginBottom: 10,
            }}
          >
            Escalade au Verdon
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6, fontSize: 12, color: 'var(--muted)' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <span
                style={{
                  width: 14,
                  height: 14,
                  borderRadius: 3,
                  background: '#F4EBD9',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontSize: 9,
                }}
              >
                📅
              </span>
              Dim. 27 avr · 8h30
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <span
                style={{
                  width: 14,
                  height: 14,
                  borderRadius: 3,
                  background: '#F4EBD9',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontSize: 9,
                }}
              >
                👥
              </span>
              4 places disponibles
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <span
                style={{
                  width: 14,
                  height: 14,
                  borderRadius: 3,
                  background: '#F4EBD9',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontSize: 9,
                }}
              >
                🎚
              </span>
              Niveau 5b — 6b
            </div>
          </div>
          <div
            style={{
              marginTop: 12,
              padding: '8px 12px',
              borderRadius: 8,
              background: NAVY,
              color: '#FFF',
              fontSize: 12,
              fontWeight: 700,
              textAlign: 'center',
            }}
          >
            Publier la sortie
          </div>
        </div>
      </div>
    );
  }

  // organize
  const messages: { who: string; msg: string; mine: boolean }[] = [
    { who: 'Léa', msg: 'Je prends 3 places en voiture 🚗', mine: false },
    { who: 'Moi', msg: 'Parfait, je viens avec toi', mine: true },
    { who: 'Tom', msg: "J'ai un casque en rab", mine: false },
  ];
  return (
    <div
      style={{
        position: 'absolute',
        inset: 0,
        padding: 20,
        display: 'flex',
        flexDirection: 'column',
        justifyContent: 'center',
        gap: 10,
      }}
    >
      {messages.map((m, i) => (
        <div
          key={i}
          style={{
            alignSelf: m.mine ? 'flex-end' : 'flex-start',
            maxWidth: '80%',
            background: m.mine ? NAVY : '#FFF',
            color: m.mine ? '#FFF' : NAVY,
            padding: '10px 14px',
            borderRadius: m.mine ? '16px 16px 4px 16px' : '16px 16px 16px 4px',
            fontSize: 13,
            lineHeight: 1.35,
            boxShadow: '0 4px 10px -2px rgba(0,0,0,0.08)',
          }}
        >
          {!m.mine && (
            <div
              style={{
                fontSize: 10,
                fontWeight: 700,
                color: ORANGE,
                marginBottom: 2,
                letterSpacing: '0.05em',
              }}
            >
              {m.who.toUpperCase()}
            </div>
          )}
          {m.msg}
        </div>
      ))}
    </div>
  );
}

export default function Pillars() {
  return (
    <section
      style={{
        padding: '140px 40px',
        background: 'var(--cream-soft)',
        position: 'relative',
        overflow: 'hidden',
      }}
    >
      <TopoLines opacity={0.05} color={NAVY} count={10} />
      <div style={{ maxWidth: 1180, margin: '0 auto', position: 'relative' }}>
        <div style={{ marginBottom: 80, maxWidth: 820 }}>
          <SectionLabel>Ce que tu fais avec Junto</SectionLabel>
          <h2
            className="display"
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
            Trouver une sortie. En créer une.{' '}
            <span style={{ color: ORANGE }}>S&apos;organiser.</span>
          </h2>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 24 }}>
          {ITEMS.map((it, i) => (
            <div
              key={i}
              style={{
                background: '#FFF',
                border: '1px solid var(--line)',
                borderRadius: 24,
                padding: '48px 56px',
                display: 'grid',
                gridTemplateColumns: 'minmax(0, 1fr) minmax(0, 320px)',
                gap: 48,
                alignItems: 'center',
              }}
            >
              <div>
                <div
                  style={{
                    display: 'inline-flex',
                    alignItems: 'baseline',
                    gap: 14,
                    marginBottom: 20,
                  }}
                >
                  <span
                    className="display"
                    style={{
                      fontSize: 56,
                      fontWeight: 800,
                      letterSpacing: '-0.04em',
                      color: ORANGE,
                      lineHeight: 0.9,
                    }}
                  >
                    {String(i + 1).padStart(2, '0')}
                  </span>
                  <span
                    className="display"
                    style={{
                      fontSize: 28,
                      fontWeight: 800,
                      letterSpacing: '-0.02em',
                      color: NAVY,
                    }}
                  >
                    {it.kicker}
                  </span>
                </div>
                <h3
                  className="display"
                  style={{
                    fontSize: 36,
                    margin: '0 0 16px',
                    fontWeight: 800,
                    letterSpacing: '-0.025em',
                    color: NAVY,
                    lineHeight: 1.05,
                    textWrap: 'balance',
                  }}
                >
                  {it.title}
                </h3>
                <p
                  style={{
                    fontSize: 17,
                    lineHeight: 1.55,
                    margin: 0,
                    color: 'var(--muted)',
                    maxWidth: 520,
                  }}
                >
                  {it.body}
                </p>
              </div>

              <div
                style={{
                  height: 220,
                  background:
                    it.art === 'map' ? '#EFE4CE' : it.art === 'create' ? ORANGE : '#F4EBD9',
                  borderRadius: 16,
                  position: 'relative',
                  overflow: 'hidden',
                }}
              >
                <PillarArt kind={it.art} />
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
