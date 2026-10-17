'use client';

import { useMemo, useState } from 'react';
import { IconCalendar, IconChevron, IconMountain, IconPin, IconUsers } from './icons';
import { difficultyLabel, formatWhen, isNew, type OutingRow } from './data';
import SportGlyph, { hasSportGlyph } from './sport-glyph';
import { norm, sportLabel, universeColor } from './tokens';

// « 1 · Rejoins une sortie » — the next departures, peers only, in the
// grammar of the app's cards. Rows come from the server (anonymous read of
// activities_with_coords); the text / sport filters run here.
export default function DeparturesBoard({ outings }: { outings: OutingRow[] }) {
  const [query, setQuery] = useState('');
  const [sport, setSport] = useState('all');

  const sports = useMemo(() => {
    const seen = new Map<string, string>();
    for (const o of outings) if (o.sport_key && !seen.has(o.sport_key)) seen.set(o.sport_key, sportLabel(o.sport_key));
    return [...seen.entries()].sort((a, b) => a[1].localeCompare(b[1], 'fr'));
  }, [outings]);

  const rows = useMemo(() => {
    const q = norm(query).trim();
    return outings.filter((o) =>
      (sport === 'all' || o.sport_key === sport)
      && (!q || norm(`${o.meeting_locality ?? ''} ${o.meeting_name ?? ''} ${o.title}`).includes(q)),
    );
  }, [outings, query, sport]);

  const footer = outings.length === 0
    ? 'Aucun départ public pour l’instant'
    : rows.length === outings.length
      ? `${outings.length} départ${outings.length > 1 ? 's' : ''} à venir`
      : `${rows.length} départ${rows.length > 1 ? 's' : ''}`;

  return (
    <section id="departs" style={{ background: '#FFFFFF' }}>
      <div className="l-wrap">
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          <h2 className="l-h2">1 · Rejoins une sortie</h2>
          <p className="l-lead">Trouve celle qui te correspond, et rejoins-la.</p>
        </div>

        <div className="l-search-row">
          <label className="l-field grow">
            <IconPin size={18} color="#6B6259" width2={2.2} />
            <span className="sr-only">Lieu</span>
            <input type="text" value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Où ? Une vallée, un village, un sommet…" />
          </label>
          <label className="l-field select">
            <IconMountain size={18} color="#6B6259" width2={2.2} />
            <span className="sr-only">Sport</span>
            <select value={sport} onChange={(e) => setSport(e.target.value)}>
              <option value="all">Tous les sports</option>
              {sports.map(([key, label]) => <option key={key} value={key}>{label}</option>)}
            </select>
            <IconChevron size={16} color="#6B6259" className="l-chev" />
          </label>
        </div>

        <div className="l-board">
          {rows.length === 0 && (
            <div className="l-board-empty">
              {outings.length === 0
                ? <>Les premières sorties publiques arrivent ici. <b>Lance la tienne, elle y apparaîtra.</b></>
                : <>Rien ici avec ces critères. <b>Lance ta sortie, elle apparaîtra ici.</b></>}
            </div>
          )}
          {rows.map((o) => {
            const color = universeColor(o.sport_category);
            const taken = o.participant_count ?? 0;
            const full = o.max_participants != null && taken >= o.max_participants;
            return (
              <a key={o.id} href={`/activity/${o.id}`} className={`l-row${full ? ' full' : ''}`}>
                <div className="l-row-bar" style={{ background: color }} />
                <div className="l-row-main">
                  <div className="l-row-title">
                    <span>{o.title}</span>
                    {isNew(o.created_at) && <span className="l-tag new">Nouveau</span>}
                    {full && <span className="l-tag full">Complet</span>}
                  </div>
                  <span className="l-pill" style={{ color }}>{hasSportGlyph(o.sport_key) ? <SportGlyph sportKey={o.sport_key} size={14} /> : <span className="dot" />}{sportLabel(o.sport_key)}<span className="sep"> · </span>{difficultyLabel(o)}</span>
                  <div className="l-meta">
                    <span><IconCalendar size={12} color="#6B6259" />{formatWhen(o.starts_at)}</span>
                    {(o.meeting_locality || o.meeting_name) && <span><IconPin size={12} color="#6B6259" />{o.meeting_locality ?? o.meeting_name}</span>}
                    {o.creator_name && <span>par {o.creator_name}</span>}
                  </div>
                </div>
                <div className="l-seats"><IconUsers size={14} color="#1F1A15" /><b>{taken}</b><i>{o.max_participants == null ? '' : `/${o.max_participants}`}</i></div>
              </a>
            );
          })}
          <div className="l-board-foot"><span>{footer}</span><a href="#telecharger">Tout voir sur la carte ›</a></div>
        </div>
      </div>
    </section>
  );
}
