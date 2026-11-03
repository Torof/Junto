import type { ReactNode } from 'react';
import {
  AskandgoMark, IconBell, IconCalendar, IconChat, IconClipboard, IconInbox, IconMessages, IconNavigation, IconPhone,
} from './icons';
import { formatPrice, type OfferRow } from './data';
import SportGlyph from './sport-glyph';
import { UNIVERSE_COLOR, universeColor } from './tokens';

// The /pros page (maquette validée 2026-11-03): same language as the landing —
// real app fragments rebuilt in HTML, no photo. Three pillars in Scott's order:
// the storefront, the organisation tool, talking to clients. The people and
// dates in the fragments are illustrative, like the launch demo.

const MOUNTAIN = UNIVERSE_COLOR.mountain;
const PIN_PATH = 'M 27 3 C 15.4 3 6 12.2 6 23.5 C 6 33.5 18.5 43.5 24.6 50.2 C 25.9 51.6 28.1 51.6 29.4 50.2 C 35.5 43.5 48 33.5 48 23.5 C 48 12.2 38.6 3 27 3 Z';

// ---------------------------------------------------------------- hero

type HeroPin = { title: string; meta: string; color: string; left: number; top: number; delay: number };

const HERO_SLOTS = [
  { left: 64, top: 22, delay: 0 }, { left: 76, top: 44, delay: 0.5 },
  { left: 58, top: 62, delay: 1.0 }, { left: 70, top: 80, delay: 1.5 },
];

function heroPins(offers: OfferRow[]): HeroPin[] {
  return offers.slice(0, HERO_SLOTS.length).map((o, i) => {
    const price = formatPrice(o.price_eur, o.price_unit);
    const meta = [o.location_name, price].filter(Boolean).join(' · ');
    return { title: o.title, meta, color: universeColor(o.sport_category), ...HERO_SLOTS[i]! };
  });
}

export function ProsHero({ offers }: { offers: OfferRow[] }) {
  return (
    <header className="l-hero" style={{ minHeight: 640 }}>
      <img className="l-hero-img" src="/hero-map-ecrins.jpg" alt="" />
      <div className="l-hero-shade" />
      <div className="l-hero-grad" />

      {heroPins(offers).map((p, i) => (
        <div key={i} className="l-pin" style={{ left: `${p.left}%`, top: `${p.top}%` }} aria-hidden>
          <div className="l-pin-dotwrap">
            <div className="l-pin-pulse" style={{ background: '#F2B705', animationDelay: `${p.delay}s` }} />
            <div className="l-pin-dot" style={{ background: p.color, borderColor: '#F2B705' }} />
          </div>
          <div className="l-pin-label">
            <div className="l-pin-title" style={{ color: p.color }}>{p.title}</div>
            {p.meta && <div className="l-pin-meta">{p.meta}</div>}
          </div>
        </div>
      ))}

      <nav className="l-nav" aria-label="Navigation principale">
        <a href="/" className="l-nav-brand"><span className="l-nav-tile"><AskandgoMark size={26} /></span><span className="l-wordmark">ask<span className="and">and</span>go</span></a>
        <div className="l-nav-links">
          <a href="/">Pratiquants</a>
          <a href="/pros" aria-current="page" style={{ color: '#FFFFFF' }}>Pros</a>
          <a href="#telecharger" className="l-nav-cta">Télécharger</a>
        </div>
      </nav>

      <div className="l-hero-body">
        <div className="l-chip-row l-rise"><span className="l-chip"><span className="l-gold">PRO</span>Guides · moniteurs · accompagnateurs</span></div>
        <h1 className="l-h1 l-rise-2">Ta vitrine. <em>Et ton outil d&apos;organisation.</em></h1>
        <p className="l-hero-sub l-rise-3">Mets tes offres en ligne, reçois tes réservations, échange avec tes clients — au même endroit.</p>
        <div className="l-chip-row l-rise-3"><a href="#telecharger" className="l-btn-white">Créer ma page pro</a></div>
      </div>
    </header>
  );
}

// ---------------------------------------------------------------- 1 · vitrine

// The app's pro outing pin: the drop in the universe colour, gold outline,
// gold « PRO » capsule under the tip (pin-style.ts, DECISIONS 2026-10-25).
function ProPin({ left, top, color, sportKey, scale = 1, label }: {
  left: number; top: number; color: string; sportKey: string; scale?: number;
  label?: { title: string; line1: string; line2: string };
}) {
  const w = Math.round(54 * scale);
  const h = Math.round(68 * scale);
  return (
    <>
      <div className="pp-pin" style={{ left: `${left}%`, top: `${top}%`, width: w, height: h }} aria-hidden>
        <svg width={w} height={h} viewBox="0 0 54 66">
          <path d={PIN_PATH} fill="#0A0F1A" opacity="0.35" transform="translate(0 3)" />
          <path d={PIN_PATH} fill="#F2B705" stroke="#F2B705" strokeWidth="4" strokeLinejoin="round" />
          <path d={PIN_PATH} fill={color} />
          <rect x="16" y="50.5" width="22" height="12" rx="6" fill="#F2B705" />
          <text x="27" y="59.3" textAnchor="middle" fontFamily="Inter, sans-serif" fontSize="7.5" fontWeight="800" fill="#1F1A15">PRO</text>
        </svg>
        <span className="pp-pin-glyph"><SportGlyph sportKey={sportKey} size={Math.round(22 * scale)} color="#FFFFFF" /></span>
      </div>
      {label && (
        <div className="pp-pin-label" style={{ left: `calc(${left}% + ${Math.round(22 * scale)}px)`, top: `calc(${top}% - ${Math.round(50 * scale)}px)` }} aria-hidden>
          <span className="t" style={{ color }}>{label.title}</span>
          <span className="s"><img src="/label-cal.png" alt="" />{label.line1}</span>
          <span className="s"><img src="/label-level.png" alt="" />{label.line2}</span>
        </div>
      )}
    </>
  );
}

// Free-licensed photos from Wikimedia Commons (public/pros/CREDITS.txt,
// credited under section 1) — never the app's demo photos, which are not ours.
const THUMBS = ['thumb-cordee.jpg', 'thumb-falaise-ecole.jpg', 'thumb-via-ferrata.jpg', 'thumb-ceuse.jpg'];

function Offer({ sportKey, photo, title, sub, price }: { sportKey: string; photo: string; title: string; sub: string; price: string }) {
  return (
    <div className="pp-offer">
      <span className="pp-ophoto">
        <img src={`/pros/${photo}`} alt="" />
        <span className="pp-disc" style={{ background: MOUNTAIN }}><SportGlyph sportKey={sportKey} size={13} color="#FFFFFF" /></span>
      </span>
      <div style={{ flex: 1, minWidth: 0 }}><div style={{ fontWeight: 800, fontSize: 14.5 }}>{title}</div><div className="l-small">{sub}</div></div>
      <div style={{ textAlign: 'right' }}><div style={{ fontWeight: 800, fontSize: 16 }}>{price}</div><span className="l-btn sm" style={{ marginTop: 4 }}>Réserver</span></div>
    </div>
  );
}

export function ProsShowcase() {
  return (
    <section style={{ background: '#FFFFFF' }}>
      <div className="l-wrap" style={{ gap: 26 }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8, maxWidth: '62ch' }}>
          <h2 className="l-h2">1 · Une vitrine, visible partout</h2>
          <p className="l-lead">Tes offres sur la carte, là où les pratiquants cherchent leur prochaine sortie.</p>
        </div>

        <div className="l-two">
          <div className="l-map" style={{ minHeight: 420, flex: '1 1 420px' }}>
            <img src="/hero-map-ecrins.jpg" alt="" style={{ objectPosition: '30% 60%' }} />
            <ProPin left={30} top={62} color={MOUNTAIN} sportKey="climbing-sport" scale={1.25} label={{ title: 'Initiation falaise', line1: '45 € · 3h', line2: 'Tous niveaux' }} />
            <ProPin left={52} top={30} color={MOUNTAIN} sportKey="via-ferrata" label={{ title: 'Via ferrata', line1: '55 € · 3h30', line2: 'Tous niveaux' }} />
            <ProPin left={48} top={80} color={UNIVERSE_COLOR.water} sportKey="canyoning" label={{ title: 'Canyon du Fournel', line1: '55 € · 4h', line2: 'Dès 12 ans' }} />
            <ProPin left={16} top={24} color={UNIVERSE_COLOR.air} sportKey="paragliding" scale={0.85} />
          </div>

          <div className="pp-page">
            <div className="pp-cover">
              <img src="/pros/cover-ecrins.jpg" alt="" />
              <span className="l-gold">PRO</span>
            </div>
            <div className="pp-ident"><div className="pp-avatar">LA</div></div>
            <div className="pp-body">
              <div style={{ minWidth: 0 }}>
                <div className="pp-name">Lise Arnaud · Escalade Écrins</div>
                <div style={{ fontSize: 12.5, color: '#6B6259', fontWeight: 600 }}>Monitrice d&apos;escalade · Ailefroide</div>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13 }}><span className="pp-stars">★★★★★</span><b>4,8</b><span className="l-muted">· 5 avis</span></div>
              <div className="pp-chips">
                <span className="pp-chip"><IconPhone size={14} color="#246342" width2={2.2} />Appeler</span>
                <span className="pp-chip"><IconChat size={14} color="#246342" width2={2.2} />Écrire</span>
                <span className="pp-chip"><IconNavigation size={14} color="#246342" width2={2.2} />Itinéraire</span>
              </div>
              <Offer sportKey="climbing-sport" photo="offer-initiation.jpg" title="Initiation falaise à Ailefroide" sub="3h · Tous niveaux · jusqu'à 6 pers." price="45 €" />
              <Offer sportKey="via-ferrata" photo="offer-via-ferrata.jpg" title="Via ferrata des Vigneaux" sub="3h30 · Tous niveaux · jusqu'à 8 pers." price="55 €" />
              <div className="pp-thumbs" aria-hidden>
                {THUMBS.map((t, i) => (
                  <div key={t} className="pp-thumb">
                    <img src={`/pros/${t}`} alt="" />
                    {i === THUMBS.length - 1 && <span className="pp-more">+8</span>}
                  </div>
                ))}
              </div>
              <div className="pp-review">« Première grande voie de ma vie avec Lise, je n&apos;ai jamais eu peur. Elle explique chaque geste. » <span className="l-muted" style={{ fontSize: 12 }}>— Marie</span></div>
            </div>
          </div>
        </div>
        <p className="pp-credits">
          Photos : <a href="https://commons.wikimedia.org/wiki/File:Pic_de_Neige_Cordier_1.jpg">Nouill</a> (CC BY 4.0),{' '}
          <a href="https://commons.wikimedia.org/wiki/File:Climbing_rock_@_Duingt_@_Hike_to_Taillefer_%26_Montagne_d%27Entrevernes_(15115775798).jpg">Guilhem Vellut</a> (CC BY 2.0),{' '}
          Kent Wang (<a href="https://commons.wikimedia.org/wiki/File:Via_Ferrata_du_Tichodrome_02.jpg">1</a>, <a href="https://commons.wikimedia.org/wiki/File:Via_Ferrata_du_Tichodrome_03.jpg">2</a>, CC BY 4.0),{' '}
          <a href="https://commons.wikimedia.org/wiki/File:Ceuse_Rock_Climbing_Area.jpg">antoine73</a> (CC BY 3.0),{' '}
          <a href="https://commons.wikimedia.org/wiki/File:Climber_and_belayer_at_Echo_T_(49411673851).jpg">Joshua Tree National Park</a> (domaine public) — via Wikimedia Commons, recadrées.
        </p>
      </div>
    </section>
  );
}

// ---------------------------------------------------------------- 2 · organisation

type Half = { kind: 'open' | 'busy' | 'booked' | 'pending'; label?: string; sportKey?: string };
const WEEK: { d: string; n: number; halves: [Half, Half] }[] = [
  { d: 'L', n: 12, halves: [{ kind: 'booked', label: '4/6' }, { kind: 'open' }] },
  { d: 'M', n: 13, halves: [{ kind: 'open' }, { kind: 'booked', label: '6/6' }] },
  { d: 'M', n: 14, halves: [{ kind: 'busy' }, { kind: 'busy' }] },
  { d: 'J', n: 15, halves: [{ kind: 'booked', label: '5/6' }, { kind: 'open' }] },
  { d: 'V', n: 16, halves: [{ kind: 'open' }, { kind: 'booked', label: '2/8', sportKey: 'via-ferrata' }] },
  { d: 'S', n: 17, halves: [{ kind: 'pending', label: '3' }, { kind: 'booked', label: '6/6' }] },
  { d: 'D', n: 18, halves: [{ kind: 'open' }, { kind: 'pending', label: '2' }] },
];
const TODAY = 14;

function HalfDay({ h }: { h: Half }) {
  if (h.kind === 'open') return <div className="pp-half open" />;
  if (h.kind === 'busy') return <div className="pp-half busy">occupé</div>;
  const color = h.kind === 'booked' ? '#FFFFFF' : MOUNTAIN;
  return (
    <div className={`pp-half ${h.kind}`}>
      <SportGlyph sportKey={h.sportKey ?? 'climbing-sport'} size={13} color={color} />
      {h.label}
    </div>
  );
}

function Tile({ icon, title, sub, children }: { icon: ReactNode; title: string; sub: string; children: ReactNode }) {
  return (
    <div className="l-tile">
      <div className="l-tile-head">
        <div className="l-tile-icon">{icon}</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}><span className="l-tile-title">{title}</span><span className="l-tile-sub">{sub}</span></div>
      </div>
      {children}
    </div>
  );
}

const GROUP: [string, string, string, string][] = [['Camille', '39', '168', '61'], ['Léo', '37', '154', '45'], ['Inès', '35', '146', '38']];

export function ProsOrganise() {
  return (
    <section style={{ background: '#FFFFFF' }}>
      <div className="l-wrap" style={{ gap: 0, paddingTop: 24 }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8, maxWidth: '62ch' }}>
          <h2 className="l-h2">2 · Un outil d&apos;organisation simple</h2>
          <p className="l-lead">Tu t&apos;y retrouves dans tes dates et tes réservations, sans tableur ni carnet à côté.</p>
        </div>
        <div className="l-org">
          <div className="l-org-head">
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              <div className="l-eyebrow">Ton espace pro</div>
              <h3>Les demandes arrivent, tout se range.</h3>
            </div>
            <p>Tu acceptes d&apos;un geste, la date se bloque dans ton agenda, le client est prévenu. Avant la sortie, sa fiche t&apos;attend.</p>
          </div>
          <div className="l-tiles">
            <Tile icon={<IconInbox size={22} color="#246342" width2={2.2} />} title="Demandes" sub="2 en attente">
              <div className="l-line"><div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}><span className="l-line-name">Camille · 3 pers.</span><span className="l-line-sub">Initiation falaise · sam. 17, matin</span></div><span className="l-btn sm">Accepter</span></div>
              <div className="l-line"><div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}><span className="l-line-name">Hugo · 2 pers.</span><span className="l-line-sub">Via ferrata · dim. 18, après-midi</span></div><span className="l-btn sm">Accepter</span></div>
              <div className="l-line dashed"><span style={{ fontSize: 13.5 }}>Aucune date ne lui va ? <b>Il t&apos;en propose une.</b></span></div>
            </Tile>

            <Tile icon={<IconCalendar size={22} color="#246342" width2={2.2} />} title="Agenda" sub="Semaine du 12 juillet · 5 sorties">
              <div className="pp-week">
                {WEEK.map((day) => (
                  <div key={day.n} className={`pp-day${day.n === TODAY ? ' today' : ''}`}>
                    <span className="d">{day.d}</span><span className="n">{day.n}</span>
                    <HalfDay h={day.halves[0]} /><HalfDay h={day.halves[1]} />
                  </div>
                ))}
              </div>
              <div className="pp-legend">
                <span><i style={{ background: MOUNTAIN }} />Réservé</span>
                <span><i style={{ border: `1.5px dashed ${MOUNTAIN}` }} />Demande</span>
                <span><i style={{ background: 'rgba(36,99,66,0.16)' }} />Dispo</span>
                <span><i style={{ background: 'rgba(160,150,138,0.22)' }} />Occupé (ton agenda)</span>
              </div>
            </Tile>

            <Tile icon={<IconClipboard size={22} color="#246342" width2={2.2} />} title="Fiches du groupe" sub="remplies par tes clients">
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}><span style={{ fontSize: 14 }}><b>Camille</b> <span className="l-muted">· sam. 17, matin</span></span><span className="l-badge-green">complète</span></div>
              <div className="pp-form">
                <div className="pp-form-row h"><span /><span>Pointure</span><span>Taille</span><span>Poids</span></div>
                {GROUP.map(([name, shoe, height, weight]) => (
                  <div key={name} className="pp-form-row"><b>{name}</b><span>{shoe}</span><span>{height}</span><span>{weight}</span></div>
                ))}
              </div>
              <div style={{ fontSize: 12, lineHeight: 1.45, color: '#6B6259' }}>Baudriers et chaussons prêts avant d&apos;arriver au pied de la falaise.</div>
            </Tile>
          </div>
        </div>
      </div>
    </section>
  );
}

// ---------------------------------------------------------------- 3 · échanges

export function ProsTalk() {
  return (
    <section style={{ background: '#FFFFFF' }}>
      <div className="l-wrap" style={{ gap: 26, paddingTop: 24 }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8, maxWidth: '62ch' }}>
          <h2 className="l-h2">3 · Parler à tes clients, très simplement</h2>
          <p className="l-lead">Une question avant de réserver, un détail la veille : tout se dit dans l&apos;app.</p>
        </div>
        <div className="l-two">
          <div className="pp-dm">
            <div className="pp-dm-head">
              <div className="l-avatar" style={{ width: 36, height: 36, fontSize: 12 }}>CM</div>
              <div style={{ display: 'flex', flexDirection: 'column' }}><b style={{ fontSize: 15 }}>Camille</b><span className="l-small">Initiation falaise · sam. 17, matin</span></div>
            </div>
            <div className="pp-dm-body">
              <div className="pp-b them">Bonjour ! On sera trois, avec mes deux ados de 12 et 14 ans. C&apos;est faisable pour eux ?</div>
              <div className="pp-b me">Bonjour Camille, oui, c&apos;est parfait dès 8 ans. Tout le matériel est fourni.</div>
              <div className="pp-b me">Samedi matin, il reste trois places.<small>9h50</small></div>
              <div className="pp-b me">📆 Réservation confirmée — « Initiation falaise à Ailefroide », le 17/07 matin (3 pers.). Paiement sur place.<small>9h58</small></div>
              <div className="pp-b them">Top ! On vient avec quoi ?<small>10h12</small></div>
            </div>
            <div className="l-chan-compose"><input type="text" placeholder="Écrire un message…" aria-label="Message (démonstration)" readOnly /></div>
          </div>

          <div className="pp-side">
            <div className="pp-card">
              <div className="l-tile-head">
                <div className="l-tile-icon"><IconMessages size={22} color="#246342" width2={2.2} /></div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}><span className="l-tile-title">Écrire à tous</span><span className="l-tile-sub">Initiation falaise · sam. 17, matin</span></div>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <div className="pp-avs" aria-hidden>{['CM', 'LE', 'IN', 'TB', 'JR'].map((x) => <span key={x}>{x}</span>)}</div>
                <span className="l-small">6 participants, 2 groupes</span>
              </div>
              <div className="l-bubble me" style={{ alignSelf: 'flex-start' }}>Rendez-vous 8h45 au parking d&apos;Ailefroide. Prévoyez de l&apos;eau et une casquette !</div>
            </div>
            <div className="pp-card inline">
              <div className="l-tile-icon"><IconBell size={22} color="#246342" width2={2.2} /></div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}><span style={{ fontWeight: 800, fontSize: 15 }}>Nouvelle demande</span><span className="l-small">Hugo · Via ferrata · dim. 18, après-midi</span></div>
            </div>
            <div className="pp-card inline">
              <div className="l-tile-icon"><IconClipboard size={22} color="#246342" width2={2.2} /></div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}><span style={{ fontWeight: 800, fontSize: 15 }}>Fiche du groupe reçue</span><span className="l-small">Camille · 3 participants · sam. 17, matin</span></div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
