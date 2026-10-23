import { IconHash, IconPlus } from './icons';
import SportGlyph from './sport-glyph';
import { RELIABILITY_BLUE } from './tokens';

// Two columns: a channel as it lives in the app (left), and the public
// profile that lets you say yes to a stranger (right). Illustrative content
// built on the app's demo personas.

// Lucide icons as the app draws them (stroke 2.2).
const HELP = ['circle:12,12,10', 'M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3', 'M12 17h.01'];
const MOUNTAIN = ['m8 3 4 8 5-5 5 15H2L8 3z'];
const USERS = ['M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2', 'circle:9,7,4', 'M22 21v-2a4 4 0 0 0-3-3.87', 'M16 3.13a4 4 0 0 1 0 7.75'];
const CLOCK = ['circle:12,12,10', 'M12 6v6l4 2'];
const PACKAGE = ['M16.5 9.4 7.55 4.24', 'M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z', 'M3.27 6.96 12 12.01l8.73-5.05', 'M12 22.08V12'];
const SHIELD = ['M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z'];

function Lucide({ d, size, color }: { d: string[]; size: number; color: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      {d.map((x) => {
        if (x.startsWith('circle:')) { const [cx, cy, r] = x.slice(7).split(','); return <circle key={x} cx={cx} cy={cy} r={r} />; }
        return <path key={x} d={x} />;
      })}
    </svg>
  );
}

// « Sports pratiqués » pill: glyph in its universe colour · ×outings · declared
// level · green triangle when partners confirmed it (grey dot when not yet judged).
function SportChip({ sportKey, color, count, level, up }: { sportKey: string; color: string; count: number; level: string; up?: boolean }) {
  return (
    <span className="l-pf-sport">
      <SportGlyph sportKey={sportKey} size={16} color={color} />
      <b>×{count}</b>
      <i />
      <span>{level}</span>
      {up
        ? <svg width="10" height="10" viewBox="0 0 24 24" aria-label="confirmé par ses partenaires"><path d="M13.73 4a2 2 0 0 0-3.46 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z" fill="#2ECC71" /></svg>
        : <span className="dot" />}
    </span>
  );
}

function Msg({ who, initials, children }: { who: string; initials: string; children: React.ReactNode }) {
  return (
    <div className="l-chan-msg">
      <div className="l-avatar" style={{ width: 32, height: 32, fontSize: 11 }}>{initials}</div>
      <div style={{ maxWidth: '82%', display: 'flex', flexDirection: 'column', gap: 3 }}>
        <div className="who">{who}</div>
        <div className="txt">{children}</div>
      </div>
    </div>
  );
}

export default function ChannelsTrust() {
  return (
    <section id="confiance" style={{ background: '#FFFFFF' }}>
      <div className="l-wrap" style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 28, alignItems: 'stretch' }}>

        <div className="l-col">
          <div className="l-eyebrow">Les canaux</div>
          <h3 className="l-h3">Des discussions qui finissent dehors.</h3>
          <div className="l-chan">
            <div className="l-chan-head">
              <div style={{ width: 40, height: 40, borderRadius: 12, background: 'rgba(255,255,255,0.18)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}><IconHash size={20} color="#FFFFFF" /></div>
              <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
                <div className="l-display" style={{ fontWeight: 800, fontSize: 16, letterSpacing: -0.2 }}>Escalade · Briançonnais</div>
                <div style={{ fontSize: 12, color: 'rgba(255,255,255,0.78)' }}>128 membres · animé par Thomas B.</div>
              </div>
              <span style={{ fontSize: 11, fontWeight: 800, color: '#0F1A14', background: '#7BD8A5', borderRadius: 999, padding: '4px 10px', flexShrink: 0 }}>Canal ouvert</span>
            </div>
            <div className="l-chan-body">
              <Msg who="Thomas B." initials="TB">Qui est chaud pour Rocher Baron samedi matin ? Du 5c au 6a, je prends la corde.</Msg>
              <Msg who="Julie R." initials="JR">Partante ! Je peux prendre deux personnes depuis Briançon.</Msg>
              <div className="l-chan-msg">
                <div className="l-avatar" style={{ width: 32, height: 32, fontSize: 11 }}>TB</div>
                <div style={{ maxWidth: '88%', display: 'flex', flexDirection: 'column', gap: 3 }}>
                  <div className="who">Thomas B. a proposé une sortie</div>
                  <div style={{ background: '#FFFFFF', border: '1.5px solid #4A7C59', borderRadius: 16, padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 8, minWidth: 260 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}><span style={{ width: 10, height: 10, borderRadius: '50%', background: '#4A7C59', flexShrink: 0 }} /><span className="l-display" style={{ fontWeight: 800, fontSize: 15 }}>Grimpe au Rocher Baron</span></div>
                    <div style={{ fontSize: 12, color: '#6B6259' }}>Samedi 9h · Villar-Saint-Pancrace · 5c à 6a</div>
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 10 }}>
                      <span style={{ fontSize: 12, fontWeight: 700 }}>3 / 6 places</span>
                      <a href="#telecharger" className="l-btn sm">Rejoindre</a>
                    </div>
                  </div>
                </div>
              </div>
              <Msg who="Karim D." initials="KD">Je débute en falaise, c&apos;est ok ?</Msg>
              <Msg who="Thomas B." initials="TB">Oui, il y a du 5b au soleil. Casque obligatoire.</Msg>
              <Msg who="Léa M." initials="LM">J&apos;ai un casque en rab si besoin !</Msg>
            </div>
            <div className="l-chan-compose">
              <label htmlFor="canal-compose" className="sr-only">Écrire dans le canal</label>
              <input id="canal-compose" type="text" placeholder="Écrire dans le canal…" readOnly />
              <a href="#telecharger" className="l-btn-outline" aria-label="Proposer une sortie"><IconPlus size={14} color="#3F7A56" width2={2.6} /><span>Proposer une sortie</span></a>
            </div>
          </div>
          <p style={{ margin: 0, fontSize: 14, lineHeight: 1.6, color: '#6B6259' }}>Un canal, c&apos;est un lieu et un sport. On y parle conditions, matos, envies — et quand quelqu&apos;un propose, la sortie apparaît dans le fil, prête à rejoindre.</p>
        </div>

        <div className="l-col">
          <div className="l-eyebrow">Partir en confiance</div>
          <h3 className="l-h3">Des inconnus, oui. Des inconnus fiables.</h3>
          {/* The app's public profile, top to bottom: name, the hero card
              (reliability ring around the avatar, tier, member line, three
              counts), « Sports pratiqués », « Ses partenaires disent… ». */}
          <div className="l-pf">
            <div className="l-pf-name">Marie L.</div>
            <div className="l-pf-card l-pf-hero">
              <div className="l-pf-ring">
                <svg width="80" height="80" viewBox="0 0 80 80" role="img" aria-label="Fiabilité 96 %">
                  <circle cx="40" cy="40" r="38" fill="none" stroke="#F1EFEA" strokeWidth="4" />
                  <circle cx="40" cy="40" r="38" fill="none" stroke={RELIABILITY_BLUE} strokeWidth="3.5" strokeLinecap="round" strokeDasharray="229 239" transform="rotate(-90 40 40)" />
                </svg>
                <div className="l-pf-disc">ML</div>
                <span className="l-pf-pct" style={{ background: RELIABILITY_BLUE }}>96%</span>
              </div>
              <div className="l-pf-hero-main">
                <div className="l-pf-label">Fiabilité <Lucide d={HELP} size={13} color="#A0968A" /></div>
                <div className="l-pf-tier" style={{ color: RELIABILITY_BLUE }}>Excellente</div>
                <div className="l-pf-member">Membre depuis mars 2026 · Briançon</div>
                <div className="l-pf-stats">
                  <div><b>20</b><small style={{ color: '#2ECC71' }}>Terminées</small></div>
                  <i />
                  <div><b>12</b><small style={{ color: '#2FA46A' }}>Créées</small></div>
                  <i />
                  <div><b>14</b><small style={{ color: '#4B7CB8' }}>Rejointes</small></div>
                </div>
              </div>
            </div>
            <div className="l-pf-card">
              <div className="l-pf-section"><Lucide d={MOUNTAIN} size={11} color="#A0968A" />Sports pratiqués</div>
              <div className="l-pf-chips">
                <SportChip sportKey="hiking" color="#E11D48" count={14} level="Avancé" up />
                <SportChip sportKey="trail-running" color="#E11D48" count={8} level="Intermédiaire" up />
                <SportChip sportKey="climbing-sport" color="#4A7C59" count={5} level="6b" />
              </div>
            </div>
            <div className="l-pf-card">
              <div className="l-pf-section"><Lucide d={USERS} size={11} color="#A0968A" />Ses partenaires disent…</div>
              <div className="l-pf-chips">
                <span className="l-pf-trait"><Lucide d={CLOCK} size={13} color="#9DA9B5" />Ponctuel<b style={{ color: '#9DA9B5' }}>12</b></span>
                <span className="l-pf-trait"><Lucide d={PACKAGE} size={13} color="#B87333" />Préparé<b style={{ color: '#B87333' }}>7</b></span>
                <span className="l-pf-trait"><Lucide d={SHIELD} size={13} color="#B87333" />Prudent<b style={{ color: '#B87333' }}>5</b></span>
              </div>
            </div>
          </div>
          <p style={{ margin: 0, fontSize: 14, lineHeight: 1.6, color: '#6B6259' }}>Pas de notes, pas d&apos;étoiles. Une seule chose vérifiée sur place : est-ce que tu viens quand tu l&apos;as dit. Le reste, ce sont tes partenaires qui le confirment, sortie après sortie.</p>
        </div>
      </div>
    </section>
  );
}
