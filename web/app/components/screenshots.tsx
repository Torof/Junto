'use client';

import { type CSSProperties, useCallback, useEffect, useState } from 'react';
import { CREAM, NAVY_DEEP, ORANGE_SOFT, SectionLabel, TopoLines } from './shared';

const SCREENS = [
  {
    src: '/screenshots/1-map.jpeg',
    title: 'La carte',
    desc: "Les sorties près de toi, d'un coup d'œil.",
    alt: 'Carte des activités autour de toi',
  },
  {
    src: '/screenshots/2-activity.jpeg',
    title: "L'activité",
    desc: "Niveau, places, départ — toutes les infos pour t'engager.",
    alt: "Détail d'une activité",
  },
  {
    src: '/screenshots/3-transport.jpeg',
    title: 'Le transport',
    desc: "Qui conduit, qui monte. Le covoiturage s'organise en deux clics.",
    alt: 'Covoiturage et préparatifs de transport',
  },
  {
    src: '/screenshots/4-gear.jpeg',
    title: 'Le matériel',
    desc: "Qui apporte quoi. Plus d'oubli, plus de doublon.",
    alt: 'Inventaire de matériel partagé',
  },
  {
    src: '/screenshots/5-chat.jpeg',
    title: 'La discussion',
    desc: 'Un fil par sortie. Fini les groupes WhatsApp interminables.',
    alt: "Chat de l'activité",
  },
  {
    src: '/screenshots/6-pro.jpeg',
    title: 'La page pro',
    desc: 'Moniteurs et guides : offres et avis réunis.',
    alt: "Page d'un professionnel",
  },
  {
    src: '/screenshots/7-profile.jpeg',
    title: 'Le profil',
    desc: "Fiabilité et badges : tu sais à qui tu as affaire, même entre inconnus.",
    alt: 'Profil, fiabilité et badges',
  },
];

export default function Screenshots() {
  const [active, setActive] = useState<number | null>(null);

  const close = useCallback(() => setActive(null), []);
  const step = useCallback(
    (dir: number) => setActive((cur) => (cur === null ? cur : (cur + dir + SCREENS.length) % SCREENS.length)),
    [],
  );

  useEffect(() => {
    if (active === null) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') close();
      else if (e.key === 'ArrowRight') step(1);
      else if (e.key === 'ArrowLeft') step(-1);
    };
    window.addEventListener('keydown', onKey);
    // Lock background scroll while the lightbox is open.
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      window.removeEventListener('keydown', onKey);
      document.body.style.overflow = prevOverflow;
    };
  }, [active, close, step]);

  const shot = active === null ? null : SCREENS[active];

  return (
    <section
      className="junto-shots"
      style={{
        padding: '140px 40px',
        background: NAVY_DEEP,
        color: '#FFF',
        overflow: 'hidden',
        position: 'relative',
      }}
    >
      <TopoLines opacity={0.04} color={CREAM} count={8} />
      <div style={{ maxWidth: 1280, margin: '0 auto', position: 'relative' }}>
        <div style={{ marginBottom: 48, maxWidth: 720 }}>
          <SectionLabel color={ORANGE_SOFT}>L&apos;app</SectionLabel>
          <h2
            className="display junto-shots-title"
            style={{
              fontSize: 'clamp(40px, 6vw, 64px)',
              lineHeight: 0.98,
              margin: 0,
              fontWeight: 800,
              letterSpacing: '-0.035em',
              textWrap: 'balance',
            }}
          >
            Pensée pour le <span style={{ color: ORANGE_SOFT }}>terrain.</span>
          </h2>
          <p
            className="mono"
            style={{ fontSize: 12, letterSpacing: '0.08em', color: 'rgba(255,255,255,0.5)', marginTop: 18 }}
          >
            Touche une capture pour l&apos;agrandir.
          </p>
        </div>

        <div
          className="junto-shots-grid"
          style={{
            display: 'flex',
            flexWrap: 'wrap',
            justifyContent: 'center',
            gap: 28,
          }}
        >
          {SCREENS.map((s, i) => (
            <div key={s.src} className="junto-shots-item" style={{ flex: '0 1 264px', maxWidth: 300 }}>
              <button
                type="button"
                onClick={() => setActive(i)}
                aria-label={`Agrandir : ${s.title}`}
                className={`junto-shots-frame ${i % 2 === 0 ? 'junto-shots-frame-even' : 'junto-shots-frame-odd'}`}
                style={{
                  display: 'block',
                  width: '100%',
                  border: 0,
                  cursor: 'zoom-in',
                  borderRadius: 32,
                  padding: 8,
                  background: 'linear-gradient(180deg, #2A3E5F 0%, #182238 100%)',
                  boxShadow:
                    '0 40px 60px -20px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,255,255,0.08)',
                  transform: i % 2 === 0 ? 'translateY(0)' : 'translateY(28px)',
                }}
              >
                <div
                  style={{
                    position: 'relative',
                    borderRadius: 26,
                    overflow: 'hidden',
                    aspectRatio: '981 / 2048',
                    background: '#000',
                  }}
                >
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    src={s.src}
                    alt={s.alt}
                    style={{
                      width: '100%',
                      height: '100%',
                      objectFit: 'contain',
                      objectPosition: 'top',
                      display: 'block',
                    }}
                  />
                  <span
                    aria-hidden
                    style={{
                      position: 'absolute',
                      bottom: 10,
                      right: 10,
                      width: 34,
                      height: 34,
                      borderRadius: '50%',
                      background: 'rgba(13,20,33,0.55)',
                      backdropFilter: 'blur(4px)',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      color: '#FFF',
                    }}
                  >
                    <ZoomIcon />
                  </span>
                </div>
              </button>
              <div style={{ padding: '28px 8px 0', textAlign: 'center' }}>
                <div
                  className="mono"
                  style={{
                    fontSize: 10,
                    color: ORANGE_SOFT,
                    letterSpacing: '0.15em',
                    marginBottom: 6,
                  }}
                >
                  0{i + 1}
                </div>
                <div
                  className="display"
                  style={{ fontSize: 20, fontWeight: 800, letterSpacing: '-0.02em' }}
                >
                  {s.title}
                </div>
                <p
                  style={{
                    margin: '8px auto 0',
                    maxWidth: 260,
                    fontSize: 14,
                    lineHeight: 1.4,
                    color: 'rgba(255,255,255,0.6)',
                    textWrap: 'balance',
                  }}
                >
                  {s.desc}
                </p>
              </div>
            </div>
          ))}
        </div>
      </div>

      {shot && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label={shot.title}
          onClick={close}
          style={{
            position: 'fixed',
            inset: 0,
            zIndex: 100,
            background: 'rgba(8,12,20,0.92)',
            backdropFilter: 'blur(6px)',
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            padding: '24px 16px',
          }}
        >
          <button
            type="button"
            onClick={close}
            aria-label="Fermer"
            style={{ ...lbBtn, position: 'absolute', top: 18, right: 18 }}
          >
            <CloseIcon />
          </button>

          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation();
              step(-1);
            }}
            aria-label="Capture précédente"
            className="junto-lb-nav"
            style={{ ...lbBtn, position: 'absolute', left: 18 }}
          >
            <ChevronIcon dir="left" />
          </button>

          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={shot.src}
            alt={shot.alt}
            onClick={(e) => e.stopPropagation()}
            style={{
              maxWidth: 'min(420px, 82vw)',
              maxHeight: '78vh',
              objectFit: 'contain',
              borderRadius: 18,
              boxShadow: '0 30px 80px -20px rgba(0,0,0,0.8)',
            }}
          />

          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation();
              step(1);
            }}
            aria-label="Capture suivante"
            className="junto-lb-nav"
            style={{ ...lbBtn, position: 'absolute', right: 18 }}
          >
            <ChevronIcon dir="right" />
          </button>

          <div style={{ textAlign: 'center', marginTop: 20, maxWidth: 360, pointerEvents: 'none' }}>
            <div className="display" style={{ fontSize: 20, fontWeight: 800, color: '#FFF' }}>
              {shot.title}
            </div>
            <p style={{ margin: '6px 0 0', fontSize: 14, lineHeight: 1.4, color: 'rgba(255,255,255,0.7)' }}>
              {shot.desc}
            </p>
          </div>
        </div>
      )}
    </section>
  );
}

const lbBtn: CSSProperties = {
  width: 48,
  height: 48,
  borderRadius: '50%',
  border: '1px solid rgba(255,255,255,0.2)',
  background: 'rgba(255,255,255,0.08)',
  color: '#FFF',
  cursor: 'pointer',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  zIndex: 1,
};

function ZoomIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden>
      <circle cx="11" cy="11" r="7" />
      <line x1="21" y1="21" x2="16.65" y2="16.65" />
      <line x1="11" y1="8" x2="11" y2="14" />
      <line x1="8" y1="11" x2="14" y2="11" />
    </svg>
  );
}

function CloseIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden>
      <line x1="18" y1="6" x2="6" y2="18" />
      <line x1="6" y1="6" x2="18" y2="18" />
    </svg>
  );
}

function ChevronIcon({ dir }: { dir: 'left' | 'right' }) {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden>
      <polyline points={dir === 'left' ? '15 18 9 12 15 6' : '9 18 15 12 9 6'} />
    </svg>
  );
}
