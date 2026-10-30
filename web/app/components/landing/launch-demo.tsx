'use client';

import { useEffect, useMemo, useRef, useState, type KeyboardEvent } from 'react';
import { IconBackpack, IconCalendar, IconCar, IconChat, IconChevron, IconPin, IconUsers } from './icons';
import SportGlyph, { LABEL_TO_KEY } from './sport-glyph';
import { MUTED, UNIVERSE_COLOR, type Universe } from './tokens';

// « 2 · Lance ta sortie » — a quick, playful demo with a live preview (nothing
// is sent): pick a sport, type a title, see the pin and the card the others
// will see. Date and time are not asked — two days from now at 9h (Scott
// 2026-10-30: the full form was too much). Then the organisation band:
// carpool · gear · chat, in the grammar of the app's three tabs.

const SPORT_UNI: Record<string, Universe> = {
  Escalade: 'mountain', 'Grande voie': 'mountain', Alpinisme: 'mountain', 'Via ferrata': 'mountain', 'Ski de rando': 'mountain',
  Canyoning: 'water', Kayak: 'water', 'Planche à voile': 'water', Parapente: 'air',
  Gravel: 'cycling', 'VTT enduro': 'cycling', Route: 'cycling', Randonnée: 'on-foot', Trail: 'on-foot', Trek: 'on-foot',
};
const GROUPS: [string, string[]][] = [
  ['Montagne', ['Escalade', 'Grande voie', 'Alpinisme', 'Via ferrata', 'Ski de rando']],
  ['Eau', ['Canyoning', 'Kayak', 'Planche à voile']],
  ['Air', ['Parapente']],
  ['Vélo', ['Gravel', 'VTT enduro', 'Route']],
  ['À pied', ['Randonnée', 'Trail', 'Trek']],
];

// The demo's outing date: two days from now, at 9h.
function demoDay(): string {
  const d = new Date(); d.setDate(d.getDate() + 2);
  return new Intl.DateTimeFormat('fr-FR', { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'Europe/Paris' }).format(d);
}
const DEMO_TIME = '9h';

// The app's map pin (src/components/pin-body.tsx + pin-style.ts): rounded-tip
// drop in the universe colour, white outline, two-layer shadow, white glyph.
// Same 54-wide design space, drawn 40 px wide.
const PIN_PATH = 'M 27 3 C 15.4 3 6 12.2 6 23.5 C 6 33.5 18.5 43.5 24.6 50.2 C 25.9 51.6 28.1 51.6 29.4 50.2 C 35.5 43.5 48 33.5 48 23.5 C 48 12.2 38.6 3 27 3 Z';
const PIN_S = 40 / 54;
function AppPin({ color, sportKey }: { color: string; sportKey?: string }) {
  return (
    <div className="l-app-pin" style={{ width: 78 * PIN_S, height: 82 * PIN_S }}>
      <svg width={78 * PIN_S} height={82 * PIN_S} viewBox="-12 -14 78 82" aria-hidden>
        <defs>
          <filter id="lp-far" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="4" /></filter>
          <filter id="lp-near" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="1.2" /></filter>
        </defs>
        <path d={PIN_PATH} fill="#0A0F1A" stroke="#0A0F1A" strokeWidth="4" strokeLinejoin="round" opacity="0.3" transform="translate(0 5)" filter="url(#lp-far)" />
        <path d={PIN_PATH} fill="#0A0F1A" stroke="#0A0F1A" strokeWidth="4" strokeLinejoin="round" opacity="0.45" transform="translate(0 2)" filter="url(#lp-near)" />
        <path d={PIN_PATH} fill="#FFFFFF" stroke="#FFFFFF" strokeWidth="4" strokeLinejoin="round" />
        <path d={PIN_PATH} fill={color} />
        {!sportKey && <circle cx="27" cy="23" r="6" fill="#FFFFFF" />}
      </svg>
      {sportKey && (
        <span className="l-app-pin-glyph" style={{ left: 39 * PIN_S, top: 37 * PIN_S }}>
          <SportGlyph sportKey={sportKey} size={24} color="#FFFFFF" />
        </span>
      )}
    </div>
  );
}

function Chev() { return <IconChevron size={16} color="#6B6259" className="l-chev" />; }

// Sport picker with the app's glyphs, grouped by universe — a native <select>
// can't show icons. Listbox semantics: arrows move, Enter picks, Escape closes.
const FLAT: string[] = GROUPS.flatMap(([, list]) => list);
function SportPicker({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(0);
  const wrapRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => { if (!wrapRef.current?.contains(e.target as Node)) setOpen(false); };
    document.addEventListener('mousedown', onDown);
    return () => document.removeEventListener('mousedown', onDown);
  }, [open]);

  const pick = (s: string) => { onChange(s); setOpen(false); };
  const onKey = (e: KeyboardEvent) => {
    if (!open) {
      if (e.key === 'ArrowDown' || e.key === 'Enter' || e.key === ' ') { e.preventDefault(); setActive(Math.max(0, FLAT.indexOf(value))); setOpen(true); }
      return;
    }
    if (e.key === 'Escape') { e.preventDefault(); setOpen(false); }
    else if (e.key === 'ArrowDown') { e.preventDefault(); setActive((i) => Math.min(FLAT.length - 1, i + 1)); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); setActive((i) => Math.max(0, i - 1)); }
    else if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); pick(FLAT[active]!); }
  };
  const glyph = (s: string) => <SportGlyph sportKey={LABEL_TO_KEY[s]} size={18} color={UNIVERSE_COLOR[SPORT_UNI[s] ?? 'mountain']} />;

  return (
    <div className="l-picker" ref={wrapRef}>
      <button
        type="button" id="f-sport" className="l-picker-btn"
        aria-haspopup="listbox" aria-expanded={open} aria-controls="f-sport-list"
        aria-activedescendant={open ? `f-sport-opt-${active}` : undefined}
        onClick={() => { setActive(Math.max(0, FLAT.indexOf(value))); setOpen((o) => !o); }}
        onKeyDown={onKey}
      >
        {value ? <>{glyph(value)}<span>{value}</span></> : <span className="l-picker-ph">Choisis un sport…</span>}
      </button>
      <Chev />
      {open && (
        <div className="l-picker-list" id="f-sport-list" role="listbox" aria-labelledby="f-sport-label">
          {GROUPS.map(([g, list]) => (
            <div key={g} role="group" aria-label={g}>
              <div className="l-picker-group">{g}</div>
              {list.map((s) => {
                const i = FLAT.indexOf(s);
                return (
                  <div
                    key={s} id={`f-sport-opt-${i}`} role="option" aria-selected={s === value}
                    className={`l-picker-opt${i === active ? ' active' : ''}${s === value ? ' selected' : ''}`}
                    onMouseEnter={() => setActive(i)} onMouseDown={(e) => { e.preventDefault(); pick(s); }}
                  >
                    {glyph(s)}<span>{s}</span>
                  </div>
                );
              })}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

export default function LaunchDemo() {
  const day = useMemo(demoDay, []);
  const [sport, setSport] = useState('');
  const [title, setTitle] = useState('');
  const level = 'tous niveaux';
  const seats = '6';
  const time = DEMO_TIME;

  const color = sport ? UNIVERSE_COLOR[SPORT_UNI[sport] ?? 'mountain'] : MUTED;
  const sportKey = sport ? LABEL_TO_KEY[sport] : undefined;
  const pvTitle = title.trim() || (sport ? `${sport} — ta sortie` : 'Ta sortie');
  const pvPlace = 'Rendez-vous à poser sur la carte';
  const when = `${day} · ${time}`;
  const whenLabel = `${day} à ${time}`;
  const levelLabel = level.charAt(0).toUpperCase() + level.slice(1);

  return (
    <section id="lancer" style={{ background: '#FFFFFF' }}>
      <div className="l-wrap" style={{ gap: 26 }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8, maxWidth: '62ch' }}>
          <h2 className="l-h2">2 · Lance ta sortie</h2>
          <p className="l-lead">Crée-la en deux minutes : essaie ici, et regarde ce que les autres verront.</p>
        </div>

        <div className="l-two">
          <form className="l-form" onSubmit={(e) => e.preventDefault()}>
            <div className="l-form-field span2">
              <span id="f-sport-label" className="l-label">Sport</span>
              <SportPicker value={sport} onChange={setSport} />
            </div>
            <div className="l-form-field span2">
              <label htmlFor="f-title" className="l-label">Titre</label>
              <input id="f-title" type="text" value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Ex : Rando à la Croix d'Aquila" maxLength={60} />
            </div>
            <div className="l-form-field span2">
              <span className="l-label">Quand</span>
              <span className="l-form-static"><IconCalendar size={16} color="#6B6259" />{day} à {time}</span>
            </div>
            <div className="l-form-foot">
              <span className="l-small">Démonstration — rien n&apos;est publié d&apos;ici. Dans l&apos;app, tu choisis le jour, l&apos;heure, le niveau et le rendez-vous.</span>
              <a href="#telecharger" className="l-btn">Publier dans l&apos;app</a>
            </div>
          </form>

          <div className="l-preview">
            <div className="l-map">
              <img src="/hero-map-ecrins.jpg" alt="" />
              <div className="l-map-pin">
                <AppPin color={color} sportKey={sportKey} />
                {/* The app's on-map label: no box — the title in the universe
                    colour, then 📅 when and 📊 level, haloed in white. */}
                <div className="l-map-label">
                  <span className="t" style={{ color: sport ? color : '#1F1A15' }}>{pvTitle}</span>
                  <span className="s"><img src="/label-cal.png" alt="" />{whenLabel}</span>
                  <span className="s"><img src="/label-level.png" alt="" />{levelLabel}</span>
                </div>
              </div>
            </div>
            <div className="l-card">
              <div className="l-row-bar" style={{ background: color }} />
              <div className="l-row-main">
                <div className="l-row-title"><span>{pvTitle}</span><span className="l-tag new">Nouveau</span></div>
                <span className="l-pill" style={{ color }}>{sportKey ? <SportGlyph sportKey={sportKey} size={14} /> : <span className="dot" />}{sport || 'Sport'}<span className="sep"> · </span>{level}</span>
                <div className="l-meta">
                  <span><IconCalendar size={12} color="#6B6259" />{when}</span>
                  <span><IconPin size={12} color="#6B6259" />{pvPlace}</span>
                  <span>par toi</span>
                </div>
              </div>
              <div className="l-seats"><IconUsers size={14} color="#1F1A15" /><b>1</b><i>/{seats}</i></div>
            </div>
          </div>
        </div>

        <div className="l-org">
          <div className="l-org-head">
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              <div className="l-eyebrow">Une fois publiée</div>
              <h3>Dedans, tout s&apos;organise.</h3>
            </div>
            <p>Qui conduit, qui apporte quoi, ce qui manque, qui est en retard : tout le monde le voit au même endroit. Personne ne relance personne.</p>
          </div>
          <div className="l-tiles">
            <div className="l-tile">
              <div className="l-tile-head">
                <div className="l-tile-icon"><IconCar size={22} color="#246342" /></div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}><span className="l-tile-title">Covoiturage</span><span className="l-tile-sub">2 voitures · 3 places restantes</span></div>
              </div>
              <div className="l-line"><div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}><span className="l-line-name">Julie R. conduit</span><span className="l-line-sub">depuis Briançon · départ 8h15</span></div><a href="#telecharger" className="l-btn sm">Une place</a></div>
              <div className="l-line"><div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}><span className="l-line-name">Karim D. conduit</span><span className="l-line-sub">depuis Gap · départ 7h30</span></div><span className="l-outline">complet</span></div>
              <div style={{ fontSize: 12, lineHeight: 1.45, color: MUTED }}>Tu conduis ? Déclare tes places, les demandes arrivent dans la sortie.</div>
            </div>
            <div className="l-tile">
              <div className="l-tile-head">
                <div className="l-tile-icon"><IconBackpack size={22} color="#246342" /></div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}><span className="l-tile-title">Matériel</span><span className="l-tile-sub">4 objets déclarés · 1 manque</span></div>
              </div>
              <div className="l-line"><span style={{ fontSize: 14 }}><b>Corde 70 m</b> <span className="l-muted">· Thomas</span></span><span className="l-badge-green">partagée</span></div>
              <div className="l-line"><span style={{ fontSize: 14 }}><b>Casques ×2</b> <span className="l-muted">· Julie</span></span><span className="l-badge-green">partagés</span></div>
              <div className="l-line dashed"><span style={{ fontSize: 14 }}>Il manque <b>une trousse de secours</b></span><a href="#telecharger" className="l-btn sm">J&apos;apporte</a></div>
            </div>
            <div className="l-tile">
              <div className="l-tile-head">
                <div className="l-tile-icon"><IconChat size={22} color="#246342" /></div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}><span className="l-tile-title">Chat de la sortie</span><span className="l-tile-sub">les participants, et personne d&apos;autre</span></div>
              </div>
              <div className="l-bubble-row"><div className="l-avatar" style={{ width: 28, height: 28, fontSize: 10 }}>KD</div><div className="l-bubble">Je serai 10 min en retard, commencez sans moi.</div></div>
              <div className="l-bubble-row"><div className="l-avatar" style={{ width: 28, height: 28, fontSize: 10 }}>JR</div><div className="l-bubble">Pas de souci, on t&apos;attend au parking. Pense à ton casque !</div></div>
              <div className="l-bubble-row me"><div className="l-bubble me">J&apos;ai mis la trace GPX, 650 m de D+.</div></div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
