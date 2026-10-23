'use client';

import { useMemo, useState } from 'react';
import { IconBackpack, IconCalendar, IconCar, IconChat, IconChevron, IconPin, IconUsers } from './icons';
import SportGlyph, { LABEL_TO_KEY } from './sport-glyph';
import { MUTED, UNIVERSE_COLOR, type Universe } from './tokens';

// « 2 · Lance ta sortie » — a demo form with a live preview (nothing is
// sent), then the organisation band: carpool · gear · chat, in the grammar
// of the app's three tabs.

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

// Next seven days, as the app's day picker would show them.
function nextDays(): string[] {
  const fmt = new Intl.DateTimeFormat('fr-FR', { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'Europe/Paris' });
  const out: string[] = [];
  for (let i = 1; i <= 7; i++) {
    const d = new Date(); d.setDate(d.getDate() + i);
    out.push(fmt.format(d));
  }
  return out;
}

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

export default function LaunchDemo() {
  const days = useMemo(nextDays, []);
  const [sport, setSport] = useState('');
  const [title, setTitle] = useState('');
  const [place, setPlace] = useState('');
  const [day, setDay] = useState(days[0] ?? '');
  const [time, setTime] = useState('9h');
  const [level, setLevel] = useState('tous niveaux');
  const [seats, setSeats] = useState('6');

  const color = sport ? UNIVERSE_COLOR[SPORT_UNI[sport] ?? 'mountain'] : MUTED;
  const sportKey = sport ? LABEL_TO_KEY[sport] : undefined;
  const pvTitle = title.trim() || (sport ? `${sport} — ta sortie` : 'Ta sortie');
  const pvPlace = place.trim() || 'Rendez-vous à poser sur la carte';
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
              <label htmlFor="f-sport" className="l-label">Sport</label>
              <select id="f-sport" value={sport} onChange={(e) => setSport(e.target.value)}>
                <option value="">Choisis un sport…</option>
                {GROUPS.map(([g, list]) => (
                  <optgroup key={g} label={g}>{list.map((s) => <option key={s} value={s}>{s}</option>)}</optgroup>
                ))}
              </select><Chev />
            </div>
            <div className="l-form-field span2">
              <label htmlFor="f-title" className="l-label">Titre</label>
              <input id="f-title" type="text" value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Ex : Rando à la Croix d'Aquila" maxLength={60} />
            </div>
            <div className="l-form-field span2">
              <label htmlFor="f-place" className="l-label">Rendez-vous</label>
              <input id="f-place" type="text" value={place} onChange={(e) => setPlace(e.target.value)} placeholder="Ex : Puy-Chalvin, parking de la ferme" maxLength={60} />
            </div>
            <div className="l-form-field">
              <label htmlFor="f-day" className="l-label">Jour</label>
              <select id="f-day" value={day} onChange={(e) => setDay(e.target.value)}>{days.map((d) => <option key={d} value={d}>{d}</option>)}</select><Chev />
            </div>
            <div className="l-form-field">
              <label htmlFor="f-time" className="l-label">Heure</label>
              <select id="f-time" value={time} onChange={(e) => setTime(e.target.value)}>{['7h', '8h', '9h', '10h', '14h', '17h30'].map((t) => <option key={t} value={t}>{t}</option>)}</select><Chev />
            </div>
            <div className="l-form-field">
              <label htmlFor="f-level" className="l-label">Niveau</label>
              <select id="f-level" value={level} onChange={(e) => setLevel(e.target.value)}>{['tous niveaux', 'débutant', 'intermédiaire', 'avancé', 'expert'].map((l) => <option key={l} value={l}>{l}</option>)}</select><Chev />
            </div>
            <div className="l-form-field">
              <label htmlFor="f-seats" className="l-label">Places</label>
              <select id="f-seats" value={seats} onChange={(e) => setSeats(e.target.value)}>{['2', '3', '4', '5', '6', '8', '10', '12'].map((n) => <option key={n} value={n}>{n}</option>)}</select><Chev />
            </div>
            <div className="l-form-foot">
              <span className="l-small">Démonstration — rien n&apos;est publié d&apos;ici. Dans l&apos;app, tu poses le rendez-vous sur la carte.</span>
              <a href="#telecharger" className="l-btn">Publier dans l&apos;app</a>
            </div>
          </form>

          <div className="l-preview">
            <div className="l-label">Ce que les autres verront</div>
            <div className="l-map">
              <img src="/hero-map-ecrins.jpg" alt="" />
              <div className="l-map-pin">
                <AppPin color={color} sportKey={sportKey} />
                {/* The app's on-map label: no box — the title in the universe
                    colour, then 📅 when and 📊 level, haloed in white. */}
                <div className="l-map-label">
                  <span className="t" style={{ color }}>{pvTitle}</span>
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
            <div style={{ fontSize: 13, lineHeight: 1.5, color: MUTED }}>Une fois publiée, les demandes pour rejoindre arrivent dans l&apos;app — et la sortie s&apos;organise dessous.</div>
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
                <div className="l-tile-icon"><IconCar size={22} color="#2FA46A" /></div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}><span className="l-tile-title">Covoiturage</span><span className="l-tile-sub">2 voitures · 3 places restantes</span></div>
              </div>
              <div className="l-line"><div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}><span className="l-line-name">Julie R. conduit</span><span className="l-line-sub">depuis Briançon · départ 8h15</span></div><a href="#telecharger" className="l-btn sm">Une place</a></div>
              <div className="l-line"><div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}><span className="l-line-name">Karim D. conduit</span><span className="l-line-sub">depuis Gap · départ 7h30</span></div><span className="l-outline">complet</span></div>
              <div style={{ fontSize: 12, lineHeight: 1.45, color: MUTED }}>Tu conduis ? Déclare tes places, les demandes arrivent dans la sortie.</div>
            </div>
            <div className="l-tile">
              <div className="l-tile-head">
                <div className="l-tile-icon"><IconBackpack size={22} color="#2FA46A" /></div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}><span className="l-tile-title">Matériel</span><span className="l-tile-sub">4 objets déclarés · 1 manque</span></div>
              </div>
              <div className="l-line"><span style={{ fontSize: 14 }}><b>Corde 70 m</b> <span className="l-muted">· Thomas</span></span><span className="l-badge-green">partagée</span></div>
              <div className="l-line"><span style={{ fontSize: 14 }}><b>Casques ×2</b> <span className="l-muted">· Julie</span></span><span className="l-badge-green">partagés</span></div>
              <div className="l-line dashed"><span style={{ fontSize: 14 }}>Il manque <b>une trousse de secours</b></span><a href="#telecharger" className="l-btn sm">J&apos;apporte</a></div>
            </div>
            <div className="l-tile">
              <div className="l-tile-head">
                <div className="l-tile-icon"><IconChat size={22} color="#2FA46A" /></div>
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
