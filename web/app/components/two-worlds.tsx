import { NAVY, ORANGE, SectionLabel, TopoLines } from './shared';
import { UaPin, RaPin, PpPin, PRO_BLUE } from './map-pins';

// Merged section (Scott 2026-07-07): "Une carte, deux mondes" + the
// "Entre passionnés" and "Avec des pros" deep-dives fused into one block.
// Each world = its real map banner (Queyras / Serre-Ponçon, the app's
// exact pins) with its full pitch below: kicker, lead, three features,
// CTA. The old standalone mockup cards (ActivityCard / StorefrontCard)
// were dropped — the map banners carry the illustration now.

type Feature = { icon: string; title: string; body: string };

const PEER_FEATURES: Feature[] = [
  {
    icon: '◎',
    title: 'Trouve',
    body: 'Une carte vivante des sorties autour de toi. Filtre par sport, date, niveau — vois qui part où, quand.',
  },
  {
    icon: '+',
    title: 'Crée',
    body: 'Lance ta propre sortie en 30 secondes. Fixe le RDV, le niveau, les places — les autres rejoignent.',
  },
  {
    icon: '⇄',
    title: 'Organise',
    body: 'Covoiturage, chat, matériel — tout vit dans la sortie. Plus de groupes WhatsApp à 40.',
  },
];

const PRO_FEATURES: Feature[] = [
  {
    icon: '✓',
    title: 'Une vitrine vérifiée',
    body: 'Guides diplômés, écoles, moniteurs — vérifiés par Junto. Pas de faux pros.',
  },
  {
    icon: '📍',
    title: 'Leur catalogue sur la carte',
    body: 'Chaque prestation est une punaise bleue, posée là où elle se passe vraiment.',
  },
  {
    icon: '★',
    title: 'Les avis, en transparence',
    body: 'Note, commente, le pro répond. Comme sur une carte que tu connais déjà.',
  },
];

function FeatureRow({ f, accent }: { f: Feature; accent: string }) {
  return (
    <div style={{ display: 'flex', gap: 14 }}>
      <span
        style={{
          width: 32,
          height: 32,
          borderRadius: 10,
          background: accent + '1E',
          color: accent,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          fontSize: 15,
          fontWeight: 700,
          flexShrink: 0,
        }}
      >
        {f.icon}
      </span>
      <div>
        <div
          className="display"
          style={{ fontSize: 17, fontWeight: 800, color: NAVY, letterSpacing: '-0.015em', marginBottom: 2 }}
        >
          {f.title}
        </div>
        <div style={{ fontSize: 14.5, lineHeight: 1.5, color: 'var(--muted)' }}>{f.body}</div>
      </div>
    </div>
  );
}

export default function TwoWorlds() {
  return (
    <section
      id="comment"
      className="junto-worlds"
      style={{
        padding: '120px 40px',
        background: 'var(--cream)',
        position: 'relative',
        overflow: 'hidden',
      }}
    >
      <TopoLines opacity={0.05} color={NAVY} count={9} />
      <div style={{ maxWidth: 1180, margin: '0 auto', position: 'relative' }}>
        <div style={{ marginBottom: 56, maxWidth: 760 }}>
          <SectionLabel>Une carte, deux mondes</SectionLabel>
          <h2
            className="display junto-worlds-title"
            style={{
              fontSize: 'clamp(40px, 6vw, 64px)',
              lineHeight: 0.98,
              margin: 0,
              fontWeight: 800,
              letterSpacing: '-0.035em',
              color: NAVY,
              textWrap: 'balance',
            }}
          >
            Des <span style={{ color: ORANGE }}>passionnés</span> et des{' '}
            <span style={{ color: PRO_BLUE }}>pros</span>, sur la même carte.
          </h2>
        </div>

        <div
          className="junto-worlds-grid"
          style={{ display: 'grid', gridTemplateColumns: 'repeat(2, minmax(0, 1fr))', gap: 24, alignItems: 'start' }}
        >
          {/* ── Monde passionnés ─────────────────────────── */}
          <div
            style={{
              background: '#FFF',
              border: `2px solid ${ORANGE}`,
              borderRadius: 20,
              overflow: 'hidden',
              display: 'flex',
              flexDirection: 'column',
            }}
          >
            <div
              role="img"
              aria-label="Carte avec des sorties entre passionnés"
              style={{ height: 180, position: 'relative', borderBottom: '1px solid var(--line)', overflow: 'hidden', flexShrink: 0 }}
            >
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src="/world-map-passionnes.jpg"
                alt=""
                style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover', display: 'block' }}
              />
              <div className="junto-hero-pin" style={{ left: '22%', top: '62%', width: 44 }}><UaPin emoji="🚵" /></div>
              <div className="junto-hero-pin" style={{ left: '48%', top: '38%', width: 44 }}><UaPin emoji="🥾" /></div>
              <div className="junto-hero-pin" style={{ left: '74%', top: '66%', width: 44 }}><UaPin emoji="🧗" /></div>
            </div>

            <div style={{ padding: '32px 36px 38px', display: 'flex', flexDirection: 'column', gap: 22, flex: 1 }}>
              <div>
                <h3
                  className="display"
                  style={{ fontSize: 30, margin: '0 0 10px', fontWeight: 800, letterSpacing: '-0.025em', color: ORANGE }}
                >
                  Entre passionnés
                </h3>
                <p style={{ fontSize: 16.5, lineHeight: 1.55, margin: 0, color: NAVY, fontWeight: 500 }}>
                  Trouve, crée ou rejoins des sorties outdoor avec d'autres passionnés, près de chez toi.
                </p>
              </div>

              {PEER_FEATURES.map((f) => (
                <FeatureRow key={f.title} f={f} accent={ORANGE} />
              ))}

            </div>
          </div>

          {/* ── Monde pros ───────────────────────────────── */}
          <div
            id="pro"
            style={{
              background: '#FFF',
              border: `2px solid ${PRO_BLUE}`,
              borderRadius: 20,
              overflow: 'hidden',
              display: 'flex',
              flexDirection: 'column',
            }}
          >
            <div
              role="img"
              aria-label="Carte avec des sorties encadrées par des pros"
              style={{ height: 180, position: 'relative', borderBottom: '1px solid var(--line)', overflow: 'hidden', flexShrink: 0 }}
            >
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src="/world-map-pros.jpg"
                alt=""
                style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover', display: 'block' }}
              />
              <div className="junto-hero-pin" style={{ left: '30%', top: '58%', width: 44 }}><RaPin emoji="🚣" /></div>
              <div className="junto-hero-pin" style={{ left: '72%', top: '44%', width: 44 }}><RaPin emoji="🏔️" /></div>
              <div className="junto-hero-pin" style={{ left: '52%', top: '70%', width: 44 }}><PpPin /></div>
            </div>

            <div style={{ padding: '32px 36px 38px', display: 'flex', flexDirection: 'column', gap: 22, flex: 1 }}>
              <div>
                <h3
                  className="display"
                  style={{ fontSize: 30, margin: '0 0 10px', fontWeight: 800, letterSpacing: '-0.025em', color: PRO_BLUE }}
                >
                  Encadré par un pro
                </h3>
                <p style={{ fontSize: 16.5, lineHeight: 1.55, margin: 0, color: NAVY, fontWeight: 500 }}>
                  Guides diplômés, écoles, moniteurs — vérifiés, avec leur catalogue de prestations posé directement sur la carte.
                </p>
              </div>

              {PRO_FEATURES.map((f) => (
                <FeatureRow key={f.title} f={f} accent={PRO_BLUE} />
              ))}

            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
