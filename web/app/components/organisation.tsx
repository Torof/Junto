import type { CSSProperties, ReactNode } from 'react';
import { CREAM, INK, INK_SOFT, ORANGE, PAPER, STONE, SectionLabel, TopoLines } from './shared';

// The four logistics pillars that make Junto an organizer, not a social feed.
// Rebuilt as on-brand brutalist "app fragments" (Scott 2026-07-08) — the real
// screenshots read poorly; these evoke each feature in the site's paper/ink
// language, crisp at any size. Only REAL features are shown (no "à trouver"
// gear state — that flow doesn't exist).

const MUT = '#8A8070';

const rowBase: CSSProperties = {
  display: 'flex',
  alignItems: 'center',
  gap: 9,
  background: '#fff',
  border: `1.5px solid ${INK}`,
  borderRadius: 11,
  padding: '8px 10px',
};

function TransportFrag() {
  const cars = [
    { name: 'Léa', from: 'Briançon · 7h00', seats: '2 places', full: false },
    { name: 'Marc', from: 'Gap · 6h30', seats: 'complet', full: true },
  ];
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 10, width: '100%' }}>
      {cars.map((c) => (
        <div key={c.name} style={{ ...rowBase, opacity: c.full ? 0.55 : 1 }}>
          <span style={{ fontSize: 18 }}>🚗</span>
          <div style={{ display: 'flex', flexDirection: 'column', lineHeight: 1.2, flex: 1, minWidth: 0 }}>
            <b style={{ fontSize: 13.5, fontWeight: 800 }}>{c.name}</b>
            <span style={{ color: MUT, fontSize: 11, fontWeight: 600 }}>{c.from}</span>
          </div>
          <span
            style={{
              fontSize: 10.5,
              fontWeight: 800,
              border: `1.5px solid ${c.full ? MUT : INK}`,
              color: c.full ? MUT : INK,
              borderRadius: 999,
              padding: '3px 8px',
              whiteSpace: 'nowrap',
            }}
          >
            {c.seats}
          </span>
          {!c.full && (
            <span
              style={{
                fontSize: 11,
                fontWeight: 800,
                color: '#fff',
                background: ORANGE,
                border: `1.5px solid ${INK}`,
                borderRadius: 8,
                padding: '5px 9px',
                boxShadow: `2px 2px 0 ${INK}`,
              }}
            >
              Demander
            </span>
          )}
        </div>
      ))}
    </div>
  );
}

function MaterielFrag() {
  const gear = [
    { item: 'Corde à double', by: 'Marc' },
    { item: 'Casque ×2', by: 'Léa' },
    { item: 'Baudriers ×2', by: 'Toi' },
  ];
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 10, width: '100%' }}>
      {gear.map((g, i) => (
        <div
          key={g.item}
          style={{
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            fontSize: 13.5,
            fontWeight: 700,
            borderBottom: i < gear.length - 1 ? `1.5px dashed ${STONE}` : 'none',
            paddingBottom: i < gear.length - 1 ? 7 : 0,
          }}
        >
          <span>{g.item}</span>
          <span style={{ color: ORANGE, fontWeight: 800 }}>✓ {g.by}</span>
        </div>
      ))}
    </div>
  );
}

function ChatFrag() {
  const bubble: CSSProperties = {
    maxWidth: '82%',
    fontSize: 13,
    fontWeight: 600,
    padding: '9px 12px',
    border: `1.5px solid ${INK}`,
    lineHeight: 1.35,
  };
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 9, width: '100%' }}>
      <div style={{ ...bubble, alignSelf: 'flex-start', background: STONE, borderRadius: '13px 13px 13px 3px' }}>
        On part à 7h du parking du Fournel ?
      </div>
      <div style={{ ...bubble, alignSelf: 'flex-end', background: `${ORANGE}26`, borderRadius: '13px 13px 3px 13px' }}>
        Nickel 👍 je prends la corde
      </div>
    </div>
  );
}

function ProfilFrag() {
  const r = 30;
  const c = 2 * Math.PI * r;
  const off = c * (1 - 0.96);
  const chip: CSSProperties = {
    fontSize: 11.5,
    fontWeight: 800,
    border: `1.5px solid ${INK}`,
    borderRadius: 999,
    padding: '4px 10px',
    background: '#fff',
  };
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12 }}>
      <svg width="86" height="86" viewBox="0 0 86 86" aria-hidden>
        <circle cx="43" cy="43" r={r} fill="none" stroke={STONE} strokeWidth="7" />
        <circle
          cx="43"
          cy="43"
          r={r}
          fill="none"
          stroke={ORANGE}
          strokeWidth="7"
          strokeLinecap="round"
          strokeDasharray={c}
          strokeDashoffset={off}
          transform="rotate(-90 43 43)"
        />
        <text x="43" y="41" textAnchor="middle" className="display" fontWeight="900" fontSize="19" fill={INK}>
          96%
        </text>
        <text x="43" y="55" textAnchor="middle" fontWeight="600" fontSize="8.5" fill={INK_SOFT} letterSpacing="1">
          FIABLE
        </text>
      </svg>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6, alignItems: 'center' }}>
        <span style={chip}>🧗 Escalade · Avancé ▲</span>
        <span style={chip}>🥾 Rando · Expert ▲</span>
      </div>
    </div>
  );
}

const PILLARS: { title: string; frag: ReactNode; body: string }[] = [
  {
    title: 'Transport',
    frag: <TransportFrag />,
    body: "Qui part d'où, à quelle heure, avec combien de places. Le covoiturage est intégré à chaque sortie.",
  },
  {
    title: 'Matériel',
    frag: <MaterielFrag />,
    body: "La liste de matos vit dans la sortie : chacun dit ce qu'il apporte. On part complet.",
  },
  {
    title: 'Chat',
    frag: <ChatFrag />,
    body: 'Un groupe par sortie, créé tout seul, avec les bonnes personnes dedans. Rien à installer.',
  },
  {
    title: 'Profil',
    frag: <ProfilFrag />,
    body: 'Tes sports, tes niveaux, ta fiabilité. Tu sais avec qui tu pars — et venir vraiment, ça se voit.',
  },
];

export default function Organisation() {
  return (
    <section
      className="junto-orga"
      style={{
        padding: '110px 40px',
        background: CREAM,
        position: 'relative',
        overflow: 'hidden',
      }}
    >
      <TopoLines opacity={0.05} color={INK} count={9} />
      <div style={{ maxWidth: 1180, margin: '0 auto', position: 'relative' }}>
        <div style={{ marginBottom: 48, maxWidth: 780 }}>
          <SectionLabel>La logistique</SectionLabel>
          <h2
            className="display junto-orga-title"
            style={{
              fontSize: 'clamp(40px, 6vw, 64px)',
              lineHeight: 0.98,
              margin: 0,
              fontWeight: 900,
              letterSpacing: '-0.035em',
              color: INK,
              textWrap: 'balance',
            }}
          >
            S&apos;organiser n&apos;a jamais été <span style={{ color: ORANGE }}>aussi simple</span>.
          </h2>
          <p style={{ fontSize: 18, lineHeight: 1.55, margin: '18px 0 0', color: INK_SOFT, maxWidth: 640 }}>
            Une sortie, ce n&apos;est pas que des partants : il faut répartir les voitures, le matos,
            se parler. Sur Junto, tout ça vit directement dans la sortie.
          </p>
        </div>

        <div
          className="junto-orga-grid"
          style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(250px, 1fr))', gap: 18 }}
        >
          {PILLARS.map((p) => (
            <div
              key={p.title}
              style={{
                background: '#FFF',
                border: `2px solid ${INK}`,
                borderRadius: 16,
                overflow: 'hidden',
                boxShadow: `4px 4px 0 ${STONE}`,
                display: 'flex',
                flexDirection: 'column',
              }}
            >
              <div
                style={{
                  height: 196,
                  borderBottom: `2px solid ${INK}`,
                  background: PAPER,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  padding: 16,
                  flexShrink: 0,
                }}
              >
                {p.frag}
              </div>
              <div style={{ padding: '20px 20px 24px' }}>
                <div
                  className="display"
                  style={{ fontSize: 21, fontWeight: 800, color: INK, letterSpacing: '-0.02em', marginBottom: 8 }}
                >
                  {p.title}
                </div>
                <p style={{ fontSize: 14.5, lineHeight: 1.55, margin: 0, color: INK_SOFT }}>{p.body}</p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
