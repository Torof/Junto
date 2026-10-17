'use client';

import { useMemo, useState } from 'react';
import { IconChevron, IconClock, IconMountain, IconPin } from './icons';
import { formatDuration, formatPrice, initials, type OfferRow } from './data';
import SportGlyph, { hasSportGlyph } from './sport-glyph';
import { norm, sportLabel, universeColor } from './tokens';

// « 4 · Encadré par un pro » — real offers (anonymous read of
// pro_offerings_with_coords), filtered here by place / activity. With no
// offer yet, the section is the pitch to pros, not an empty grid.
export default function Pros({ offers }: { offers: OfferRow[] }) {
  const [query, setQuery] = useState('');
  const [sport, setSport] = useState('all');

  const sports = useMemo(() => {
    const seen = new Map<string, string>();
    for (const o of offers) if (o.sport_key && !seen.has(o.sport_key)) seen.set(o.sport_key, sportLabel(o.sport_key));
    return [...seen.entries()].sort((a, b) => a[1].localeCompare(b[1], 'fr'));
  }, [offers]);

  const list = useMemo(() => {
    const q = norm(query).trim();
    return offers.filter((o) =>
      (sport === 'all' || o.sport_key === sport)
      && (!q || norm(`${o.location_name ?? ''} ${o.title} ${o.pro_name ?? ''}`).includes(q)),
    );
  }, [offers, query, sport]);

  return (
    <section id="pros" style={{ background: '#E6EEFB' }}>
      <div className="l-wrap">
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10, maxWidth: '64ch' }}>
          <h2 className="l-h2" style={{ display: 'flex', alignItems: 'center', gap: 14, flexWrap: 'wrap' }}>
            <span>4 · Encadré par un pro</span>
            <span className="l-pro-badge" style={{ width: 34, height: 34, fontSize: 11 }}>PRO</span>
          </h2>
          <p className="l-lead">Les sorties des guides, moniteurs et bureaux, à réserver.</p>
          <p style={{ margin: 0, fontSize: 15, lineHeight: 1.6, color: '#6B6259', maxWidth: '52ch' }}>Choisis l&apos;activité, dis où tu seras — les offres apparaissent, tu réserves dans l&apos;app.</p>
        </div>

        {offers.length > 0 && (
          <div className="l-search-row">
            <label className="l-field grow">
              <IconPin size={18} color="#6B6259" width2={2.2} />
              <span className="sr-only">Lieu</span>
              <input type="text" value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Où ? Une vallée, un village, une station…" />
            </label>
            <label className="l-field select">
              <IconMountain size={18} color="#6B6259" width2={2.2} />
              <span className="sr-only">Activité</span>
              <select value={sport} onChange={(e) => setSport(e.target.value)}>
                <option value="all">Toutes les activités</option>
                {sports.map(([key, label]) => <option key={key} value={key}>{label}</option>)}
              </select>
              <IconChevron size={16} color="#6B6259" className="l-chev" />
            </label>
          </div>
        )}

        {offers.length > 0 && list.length === 0 && (
          <div className="l-offer-empty">Pas d&apos;offre ici pour cette activité — élargis le lieu, ou change d&apos;activité.</div>
        )}

        {list.length > 0 && (
          <div className="l-offers">
            {list.map((o) => {
              const color = universeColor(o.sport_category);
              const duration = formatDuration(o.duration);
              const price = formatPrice(o.price_eur, o.price_unit);
              return (
                <a key={o.id} href={`/pro/offering/${o.id}`} className="l-offer">
                  <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                    <span className="l-display" style={{ width: 38, height: 38, borderRadius: '50%', background: 'rgba(37,99,235,0.14)', color: '#2563EB', fontWeight: 800, fontSize: 13, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>{initials(o.pro_name)}</span>
                    <span style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column' }}>
                      <span style={{ fontWeight: 700, fontSize: 14, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{o.pro_name ?? 'Pro'}</span>
                      <span style={{ fontSize: 12, color: '#6B6259' }}>{o.schedule_text ?? 'Sur réservation'}</span>
                    </span>
                    <span className="l-pro-badge" style={{ width: 26, height: 26, fontSize: 9 }}>PRO</span>
                  </div>
                  <div className="l-offer-title">{o.title}</div>
                  <span className="l-pill" style={{ color }}>{hasSportGlyph(o.sport_key) ? <SportGlyph sportKey={o.sport_key} size={14} /> : <span className="dot" />}{sportLabel(o.sport_key)}{o.level && <><span className="sep"> · </span>{o.level}</>}</span>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 4, fontSize: 12, fontWeight: 500, color: '#6B6259' }}>
                    {o.location_name && <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5 }}><IconPin size={12} color="#6B6259" />{o.location_name}</span>}
                    {duration && <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5 }}><IconClock size={12} color="#6B6259" />{duration}</span>}
                  </div>
                  <div style={{ display: 'flex', justifyContent: 'flex-end', alignItems: 'center', gap: 10, marginTop: 'auto', paddingTop: 4 }}>
                    {price && <span className="l-display" style={{ fontWeight: 800, fontSize: 18 }}>{price}</span>}
                    <span className="l-btn sm" style={{ fontSize: 12 }}>Réserver</span>
                  </div>
                </a>
              );
            })}
          </div>
        )}

        <div className="l-pro-pitch">
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6, maxWidth: '60ch' }}>
            <strong style={{ fontSize: 16 }}>Vous êtes guide, moniteur, ou un bureau ?</strong>
            <span style={{ fontSize: 15, lineHeight: 1.6, color: '#6B6259' }}>Une vitrine, vos offres épinglées sur la carte, un agenda, les réservations et les échanges clients — dans l&apos;app, sans commission.</span>
          </div>
          <a href="#telecharger" className="l-btn" style={{ background: '#2563EB' }}>Créer ma page pro</a>
        </div>
      </div>
    </section>
  );
}
