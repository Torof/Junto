import { IconCalendar, IconPin } from './icons';
import SportGlyph, { LABEL_TO_KEY } from './sport-glyph';
import { UNIVERSE_COLOR, type Universe } from './tokens';

// « 3 · Trouve des partenaires » — Discovery cards in a slow marquee. These
// are the app's demo personas (illustration): real dispos are only shown to
// matching members inside the app, never on the open web.

const SPORT_U: Record<string, Universe> = {
  Rando: 'on-foot', Trail: 'on-foot', Escalade: 'mountain', 'Grande voie': 'mountain', Alpi: 'mountain', 'Ski de rando': 'mountain',
  Canyoning: 'water', 'Planche à voile': 'water', Natation: 'water', Parapente: 'air', Enduro: 'cycling', Gravel: 'cycling',
};
const REL: Record<string, [string, string]> = { excellent: ['Excellente', '#2FA46A'], good: ['Bonne', '#3F7A56'], fair: ['Correcte', '#B8860B'] };

type Dispo = { name: string; initials: string; rel: keyof typeof REL; distance: string; period: string; radius: string; sports: [string, string][]; intents: string[]; about: string };
const DISPOS: Dispo[] = [
  { name: 'Marie L.', initials: 'ML', rel: 'excellent', distance: 'à 6 km', period: 'ce week-end', radius: 'dans un rayon de 30 km', sports: [['Rando', 'avancé'], ['Trail', 'intermédiaire']], intents: ['Tranquille', 'Régulier'], about: 'Rando & trail dans les Écrins. Rythme tranquille, pique-nique au sommet.' },
  { name: 'Thomas B.', initials: 'TB', rel: 'good', distance: 'à 11 km', period: 'soirs de semaine', radius: 'dans un rayon de 15 km', sports: [['Escalade', '6b'], ['Grande voie', '6a']], intents: ['Même niveau', 'Après le boulot'], about: 'Grimpeur, toujours partant pour une couenne. Cordes en commun.' },
  { name: 'Julie R.', initials: 'JR', rel: 'excellent', distance: 'à 18 km', period: 'tous les week-ends', radius: 'dans un rayon de 15 km', sports: [['Escalade', '6a'], ['Alpi', 'AD']], intents: ['Sortie longue', 'Perf'], about: 'Grimpeuse depuis dix ans, à l’aise en couenne comme en grande voie. Cordées sérieuses, journées complètes.' },
  { name: 'Karim D.', initials: 'KD', rel: 'fair', distance: 'à 24 km', period: 'en semaine', radius: 'peu importe', sports: [['Parapente', 'autonome'], ['Rando', 'intermédiaire']], intents: ['Tôt le matin', 'Solo bienvenu'], about: 'Marche-vol surtout. Décollage tôt, je redescends toujours à pied. Ouvert aux curieux.' },
  { name: 'Léa M.', initials: 'LM', rel: 'fair', distance: 'à 32 km', period: 'ce week-end', radius: 'dans un rayon de 50 km', sports: [['Ski de rando', 'S2'], ['Canyoning', 'v3']], intents: ['Découverte', 'Convivial'], about: 'Multi-activités outdoor, selon la saison et la météo.' },
  { name: 'Nadia K.', initials: 'NK', rel: 'excellent', distance: 'à 44 km', period: 'soirs + week-end', radius: 'dans un rayon de 50 km', sports: [['Enduro', 'avancé'], ['Gravel', 'avancé']], intents: ['Après le boulot', 'Régulier', 'Challenge'], about: 'Enduro ou gravel selon la météo. Je roule à un rythme soutenu mais j’attends en haut !' },
  { name: 'Hugo P.', initials: 'HP', rel: 'fair', distance: 'à 9 km', period: 'dim. matin', radius: 'dans un rayon de 10 km', sports: [['Trail', 'avancé']], intents: ['Entraînement', 'Perf'], about: 'Trail le matin avant le travail, sortie longue le dimanche. Objectif premier ultra.' },
  { name: 'Camille V.', initials: 'CV', rel: 'good', distance: 'à 46 km', period: 'ce week-end', radius: 'dans un rayon de 30 km', sports: [['Planche à voile', 'débutant'], ['Natation', 'avancé']], intents: ['Découverte', 'Photo'], about: 'Nouvelle dans la région ! Partante pour découvrir d’autres spots et d’autres sports.' },
];

function Card({ m }: { m: Dispo }) {
  const [relLabel, relColor] = REL[m.rel]!;
  return (
    <div className="l-dispo">
      <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
        <div className="l-avatar" style={{ width: 56, height: 56, fontSize: 16 }}>{m.initials}</div>
        <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 3 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, minWidth: 0 }}>
            <span className="l-dispo-name">{m.name}</span>
            <span className="l-rel" style={{ color: relColor, background: `${relColor}1A` }}>{relLabel}</span>
          </div>
          <div style={{ fontSize: 13, color: '#6B6259' }}>{m.distance}</div>
        </div>
      </div>
      <div className="l-meta">
        <span><IconCalendar size={12} color="#6B6259" />{m.period}</span><span>·</span>
        <span><IconPin size={12} color="#6B6259" />{m.radius}</span>
      </div>
      <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
        {m.sports.map(([n, lvl]) => {
          const c = UNIVERSE_COLOR[SPORT_U[n] ?? 'mountain'];
          return <span key={n} className="l-spill" style={{ color: c, background: `${c}1A` }}><SportGlyph sportKey={LABEL_TO_KEY[n]} size={14} />{n} · {lvl}</span>;
        })}
      </div>
      <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>{m.intents.map((i) => <span key={i} className="l-intent">{i}</span>)}</div>
      <div className="l-clamp2">{m.about}</div>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 10, marginTop: 'auto' }}>
        <span style={{ fontSize: 13, fontWeight: 700, color: '#246342' }}>Inviter</span>
        <a href="#telecharger" className="l-btn list" style={{ fontSize: 13, padding: '10px 18px' }}>Contacter</a>
      </div>
    </div>
  );
}

export default function Partners() {
  const list = [...DISPOS, ...DISPOS]; // doubled for a seamless loop
  return (
    <section id="partenaires" style={{ background: '#F1EFEA', overflow: 'hidden' }}>
      <div className="l-wrap" style={{ padding: '72px 5% 0', gap: 8 }}>
        <h2 className="l-h2">3 · Trouve des partenaires</h2>
        <p className="l-lead">Dis quand tu es dispo, pour quels sports, dans quelle zone — et vois qui cherche la même chose.</p>
      </div>
      <div className="l-marquee">
        <div className="l-track">{list.map((m, i) => <Card key={`${m.name}-${i}`} m={m} />)}</div>
      </div>
    </section>
  );
}
