import { IconHash, IconPlus } from './icons';
import SportGlyph from './sport-glyph';
import { RELIABILITY_BLUE } from './tokens';

// Two columns: a channel as it lives in the app (left), and the public
// profile that lets you say yes to a stranger (right). Illustrative content
// built on the app's demo personas.

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
          <div className="l-profile">
            <div style={{ display: 'flex', gap: 14, alignItems: 'center' }}>
              <div className="l-avatar" style={{ width: 56, height: 56, fontSize: 18 }}>ML</div>
              <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 3 }}>
                <div className="l-display" style={{ fontWeight: 800, fontSize: 20, letterSpacing: -0.3 }}>Marie L.</div>
                <div style={{ fontSize: 13, color: '#6B6259' }}>Membre depuis mars 2026 · Briançon</div>
              </div>
            </div>
            <div style={{ display: 'flex', gap: 16, alignItems: 'center' }}>
              <div style={{ position: 'relative', width: 84, height: 84, flexShrink: 0 }}>
                <svg width="84" height="84" viewBox="0 0 84 84" role="img" aria-label="Fiabilité 96 %"><circle cx="42" cy="42" r="36" fill="none" stroke="rgba(31,26,21,0.08)" strokeWidth="8" /><circle cx="42" cy="42" r="36" fill="none" stroke={RELIABILITY_BLUE} strokeWidth="8" strokeLinecap="round" strokeDasharray="217 226" transform="rotate(-90 42 42)" /></svg>
                <div className="l-display" style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 800, fontSize: 18 }}>96 %</div>
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
                <div style={{ fontSize: 12, fontWeight: 700, letterSpacing: 1, textTransform: 'uppercase', color: '#6B6259' }}>Fiabilité</div>
                <div className="l-display" style={{ fontWeight: 800, fontSize: 20, color: RELIABILITY_BLUE }}>Excellente</div>
                <div style={{ fontSize: 13, lineHeight: 1.4, color: '#6B6259' }}>20 présences vérifiées sur place, par QR ou géolocalisation.</div>
              </div>
            </div>
            <div className="l-stats3">
              <div><b>12</b><small>sorties créées</small></div>
              <div><b>20</b><small>rejointes</small></div>
              <div><b>0</b><small>absence</small></div>
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              <div style={{ fontSize: 12, fontWeight: 700, letterSpacing: 1, textTransform: 'uppercase', color: '#6B6259' }}>Niveaux confirmés par ses partenaires</div>
              <div className="l-kv"><span className="l-spill" style={{ color: '#E11D48', background: '#E11D481A' }}><SportGlyph sportKey="hiking" size={14} />Rando · avancée</span><span style={{ fontSize: 12, color: '#6B6259' }}>Validé 5 fois par la commu.</span></div>
              <div className="l-kv"><span className="l-spill" style={{ color: '#E11D48', background: '#E11D481A' }}><SportGlyph sportKey="trail-running" size={14} />Trail · intermédiaire</span><span style={{ fontSize: 12, color: '#6B6259' }}>Validé 3 fois par la commu.</span></div>
              <div className="l-kv"><span className="l-spill" style={{ color: '#4A7C59', background: '#4A7C591A' }}><SportGlyph sportKey="climbing-sport" size={14} />Escalade · 6b</span><span style={{ fontSize: 12, color: '#6B6259' }}>Validé 2 fois par la commu.</span></div>
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              <div style={{ fontSize: 12, fontWeight: 700, letterSpacing: 1, textTransform: 'uppercase', color: '#6B6259' }}>Ce que disent ceux qui sont sortis avec elle</div>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
                <span className="l-trait">Ponctuelle <b>· 9</b></span>
                <span className="l-trait">Préparée <b>· 6</b></span>
                <span className="l-trait">Prudente <b>· 4</b></span>
              </div>
            </div>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, alignItems: 'center' }}>
              <span className="l-award" style={{ background: '#B8860B' }}>Pilier</span>
              <span className="l-award" style={{ background: '#8A8F98' }}>Animatrice</span>
              <span style={{ fontSize: 12, color: '#6B6259' }}>· gagnés sortie après sortie</span>
            </div>
          </div>
          <p style={{ margin: 0, fontSize: 14, lineHeight: 1.6, color: '#6B6259' }}>Pas de notes, pas d&apos;étoiles. Une seule chose vérifiée sur place : est-ce que tu viens quand tu l&apos;as dit. Le reste, ce sont tes partenaires qui le confirment, sortie après sortie.</p>
        </div>
      </div>
    </section>
  );
}
