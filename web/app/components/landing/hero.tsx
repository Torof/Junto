import { AskandgoMark, IconPlus, IconSearch, IconUsers } from './icons';
import { formatWhen, type OfferRow, type OutingRow } from './data';
import { universeColor, type Universe, UNIVERSE_COLOR } from './tokens';

type Pin = { title: string; meta: string | null; color: string; left: number; top: number; delay: number };

// Pins live on the right 55 % of the map (the text owns the left). Six
// slots; filled with real upcoming outings first, then real pro offers, then
// plain sport names — the map is never empty and never lies.
const SLOTS = [
  { left: 58, top: 22, delay: 0 }, { left: 84, top: 30, delay: 0.3 }, { left: 72, top: 48, delay: 0.7 },
  { left: 56, top: 64, delay: 1.3 }, { left: 78, top: 76, delay: 1.7 }, { left: 62, top: 86, delay: 1.0 },
];
const FALLBACK: { title: string; uni: Universe }[] = [
  { title: 'Randonnée', uni: 'on-foot' }, { title: 'Escalade', uni: 'mountain' }, { title: 'Canyoning', uni: 'water' },
  { title: 'Parapente', uni: 'air' }, { title: 'Gravel', uni: 'cycling' }, { title: 'Ski de rando', uni: 'mountain' },
];

function buildPins(outings: OutingRow[], offers: OfferRow[]): Pin[] {
  const items: Omit<Pin, 'left' | 'top' | 'delay'>[] = [];
  for (const o of outings) {
    const left = (o.max_participants ?? 0) - (o.participant_count ?? 0);
    const places = o.max_participants == null ? 'ouverte à tous' : left > 0 ? `${left} place${left > 1 ? 's' : ''}` : 'complet';
    items.push({ title: o.title, meta: `${formatWhen(o.starts_at)} · ${places}`, color: universeColor(o.sport_category) });
    if (items.length === SLOTS.length) break;
  }
  for (const f of offers) {
    if (items.length === SLOTS.length) break;
    items.push({ title: f.title, meta: 'encadré par un pro', color: universeColor(f.sport_category) });
  }
  for (const f of FALLBACK) {
    if (items.length === SLOTS.length) break;
    items.push({ title: f.title, meta: null, color: UNIVERSE_COLOR[f.uni] });
  }
  return items.map((it, i) => ({ ...it, ...SLOTS[i]! }));
}

export default function Hero({ outings, offers, playUrl }: { outings: OutingRow[]; offers: OfferRow[]; playUrl: string }) {
  const pins = buildPins(outings, offers);
  const proCount = new Set(offers.map((o) => o.pro_id)).size;
  // Counters only when they are something to say (never « 1 sortie »).
  const chips: { dot?: boolean; text: string }[] = [];
  if (outings.length >= 3) chips.push({ dot: true, text: `${outings.length} sorties à venir` });
  if (proCount >= 2) chips.push({ text: `${proCount} guides et moniteurs` });
  if (chips.length === 0) chips.push({ dot: true, text: '41 sports · 5 univers' });

  return (
    <header className="l-hero">
      <img className="l-hero-img" src="/hero-map-ecrins.jpg" alt="" />
      <div className="l-hero-shade" />
      <div className="l-hero-grad" />

      {pins.map((p, i) => (
        <div key={i} className="l-pin" style={{ left: `${p.left}%`, top: `${p.top}%` }} aria-hidden>
          <div className="l-pin-dotwrap">
            <div className="l-pin-pulse" style={{ background: p.color, animationDelay: `${p.delay}s` }} />
            <div className="l-pin-dot" style={{ background: p.color }} />
          </div>
          <div className="l-pin-label">
            <div className="l-pin-title" style={{ color: p.color }}>{p.title}</div>
            {p.meta && <div className="l-pin-meta">{p.meta}</div>}
          </div>
        </div>
      ))}

      <nav className="l-nav" aria-label="Navigation principale">
        <a href="#" className="l-nav-brand"><AskandgoMark /><span>askandgo</span></a>
        <div className="l-nav-links">
          <a href="#departs">Rejoindre</a>
          <a href="#lancer">Lancer</a>
          <a href="#partenaires">Partenaires</a>
          <a href="#pros">Pros</a>
          <a href="#telecharger" className="l-nav-cta">Télécharger</a>
        </div>
      </nav>

      <div className="l-hero-body">
        <div className="l-chip-row l-rise">
          {chips.map((c) => (
            <span key={c.text} className="l-chip">{c.dot && <span className="l-chip-dot" />}{c.text}</span>
          ))}
        </div>
        <h1 className="l-h1 l-rise-2">Ta prochaine aventure est déjà <em>sur la carte.</em></h1>
        <p className="l-hero-sub l-rise-3">Tu arrives sur une carte. Quatre choses à y faire :</p>
        <div className="l-paths l-rise-3">
          <a href="#departs" className="l-path">
            <span className="l-path-icon"><IconSearch size={20} color="#FFFFFF" width2={2.2} /></span>
            <span className="l-path-text"><span className="l-path-title"><span className="n">1 · </span>Rejoins une sortie</span><span className="l-path-sub">Vois ce qui part autour de toi</span></span>
          </a>
          <a href="#lancer" className="l-path">
            <span className="l-path-icon"><IconPlus size={20} color="#FFFFFF" /></span>
            <span className="l-path-text"><span className="l-path-title"><span className="n">2 · </span>Lance ta sortie</span><span className="l-path-sub">Les autres la voient et rejoignent</span></span>
          </a>
          <a href="#partenaires" className="l-path">
            <span className="l-path-icon"><IconUsers size={20} color="#FFFFFF" width2={2.2} /></span>
            <span className="l-path-text"><span className="l-path-title"><span className="n">3 · </span>Trouve des partenaires</span><span className="l-path-sub">Dis quand tu es dispo</span></span>
          </a>
          <a href="#pros" className="l-path">
            <span className="l-path-icon pro">PRO</span>
            <span className="l-path-text"><span className="l-path-title"><span className="n">4 · </span>Trouve un pro</span><span className="l-path-sub">Guide, moniteur, bureau — et réserve</span></span>
          </a>
        </div>
        <div className="l-chip-row l-rise-3">
          <a href={playUrl} className="l-btn-white">Télécharger sur Android</a>
        </div>
      </div>
    </header>
  );
}
