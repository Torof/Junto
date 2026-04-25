/* Carte V3 — minimaliste : 2 améliorations ciblées sur le pattern existant.
   (a) FAB + boutons filtres/géoloc en CARRÉS arrondis (plus affirmés que ronds)
   (b) Drawer replié retravaillé : titre "7 résultats" plus gros, grip plus visible, CTA "Voir la liste"
   Tout le reste respecte l'existant : pas de chips, pas de search, pins avec badge compteur vert + cadenas rouge.
*/

function TopoMapV3() {
  return (
    <svg viewBox="0 0 390 640" preserveAspectRatio="xMidYMid slice" style={{ position:'absolute', inset: 0, width:'100%', height:'100%' }}>
      {/* Style Mapbox outdoor-ish : vert végétation + routes blanches/jaunes + contours */}
      <rect width="390" height="640" fill="#D8E4C8"/>

      {/* Forest patches darker */}
      <path d="M 0 0 L 180 0 L 220 100 L 140 180 L 40 220 L 0 180 Z" fill="#A8BD93" opacity="0.8"/>
      <path d="M 240 0 L 390 0 L 390 140 L 300 160 L 250 80 Z" fill="#A8BD93" opacity="0.75"/>
      <path d="M 0 360 L 120 400 L 160 500 L 80 580 L 0 600 Z" fill="#9FB488" opacity="0.85"/>
      <path d="M 270 380 L 390 360 L 390 540 L 320 560 L 280 460 Z" fill="#A8BD93" opacity="0.75"/>

      {/* Water */}
      <path d="M 180 0 Q 200 60 190 120 Q 170 180 200 240 Q 220 310 180 380 Q 150 440 180 520 Q 200 580 180 640"
        fill="none" stroke="#8FB4C8" strokeWidth="3" opacity="0.7"/>

      {/* Contours */}
      <g fill="none" stroke="#8A7A52" strokeWidth="0.5" opacity="0.4">
        {Array.from({ length: 12 }).map((_, i) => (
          <path key={i} d={`M ${-20 + i*5} ${50 + i*42} Q ${100 + i*3} ${30 + i*38} ${230 + i*2} ${60 + i*40} T ${420} ${55 + i*38}`}/>
        ))}
        <circle cx="70" cy="100" r="20" />
        <circle cx="70" cy="100" r="34" />
        <circle cx="70" cy="100" r="48" />
        <circle cx="330" cy="60" r="16" />
        <circle cx="330" cy="60" r="28" />
        <circle cx="120" cy="460" r="18" />
        <circle cx="120" cy="460" r="32" />
      </g>

      {/* Roads */}
      <g fill="none" stroke="#FFFFFF" strokeWidth="3" opacity="0.95">
        <path d="M 0 300 Q 120 290 200 310 Q 280 330 390 310"/>
      </g>
      <g fill="none" stroke="#F2B566" strokeWidth="1.8" opacity="0.9">
        <path d="M 0 300 Q 120 290 200 310 Q 280 330 390 310"/>
      </g>
      <g fill="none" stroke="#FFFFFF" strokeWidth="1.2" opacity="0.7">
        <path d="M 200 310 Q 240 360 260 440"/>
        <path d="M 120 292 Q 100 360 120 460"/>
      </g>

      {/* Altitude labels (on map tiles, gratuit) */}
      <g fontFamily="'JetBrains Mono', monospace" fontSize="7" fill="#6B5A32" opacity="0.7" fontWeight="600">
        <text x="90" y="103">2340 m</text>
        <text x="345" y="63">2180 m</text>
        <text x="138" y="463">2520 m</text>
      </g>

      {/* Peak markers */}
      <g fill="#6B5A32">
        <polygon points="68,92 74,100 62,100" opacity="0.8"/>
        <polygon points="328,52 334,60 322,60" opacity="0.8"/>
        <polygon points="118,452 124,460 112,460" opacity="0.8"/>
      </g>
    </svg>
  );
}

// Pin respectant le pattern existant : emoji dans "goutte" blanche + badge compteur vert ou rouge+cadenas
function ExistingPin({ top, left, sport, count, full }) {
  return (
    <div style={{
      position:'absolute', top, left,
      transform:'translate(-50%, -100%)',
    }}>
      <div style={{ position: 'relative', width: 48, height: 56 }}>
        {/* White drop shape */}
        <svg width="48" height="56" viewBox="0 0 48 56" style={{ position: 'absolute', inset: 0 }}>
          <path d="M 24 2 C 12 2 4 10 4 22 C 4 34 24 54 24 54 C 24 54 44 34 44 22 C 44 10 36 2 24 2 Z"
            fill="#FFFFFF" stroke="rgba(10,15,26,0.2)" strokeWidth="1"
            filter="drop-shadow(0 3px 6px rgba(10,15,26,0.35))"/>
        </svg>
        {/* Sport emoji */}
        <div style={{
          position:'absolute', left: 10, top: 8, width: 28, height: 28,
          display:'flex', alignItems:'center', justifyContent:'center',
          fontSize: 20, lineHeight: 1,
        }}>{sport}</div>
        {/* Count or lock badge */}
        <div style={{
          position: 'absolute', top: 0, right: -2,
          width: 20, height: 20, borderRadius: '50%',
          background: full ? '#E5524E' : '#5AB573',
          border: '2px solid #FFFFFF',
          display:'flex', alignItems:'center', justifyContent:'center',
          color:'#FFF',
          fontFamily: "'Archivo', sans-serif",
          fontSize: 10, fontWeight: 800,
        }}>
          {full ? (
            <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="#FFF" strokeWidth="3" strokeLinecap="round"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
          ) : count}
        </div>
      </div>
    </div>
  );
}

function ClusterV3({ top, left, count }) {
  return (
    <div style={{
      position:'absolute', top, left, transform:'translate(-50%, -50%)',
      width: 38, height: 38, borderRadius: '50%',
      background: '#0D1626', color: '#FFF',
      display:'flex', alignItems:'center', justifyContent:'center',
      fontFamily: "'Archivo', sans-serif", fontSize: 15, fontWeight: 800,
      boxShadow: '0 4px 12px -2px rgba(10,15,26,0.5), 0 0 0 3px rgba(255,255,255,0.9)',
    }}>{count}</div>
  );
}

// Square rounded button — la nouveauté forme
function SquareBtn({ children, size = 46, variant = 'white', big = false }) {
  const styles = {
    white:  { bg: '#FFFFFF',   fg: '#0D1626' },
    dark:   { bg: '#0D1626',   fg: '#F26B2E' },
    primary:{ bg: 'linear-gradient(135deg, #F26B2E 0%, #D85519 100%)', fg: '#FFF' },
  };
  const s = styles[variant];
  return (
    <button style={{
      width: size, height: size, borderRadius: big ? 16 : 12,
      background: s.bg, color: s.fg, border: 'none',
      display:'flex', alignItems:'center', justifyContent:'center',
      boxShadow: big
        ? '0 10px 24px -4px rgba(242,107,46,0.5), 0 0 0 3px rgba(242,107,46,0.12)'
        : '0 4px 12px -2px rgba(10,15,26,0.3)',
      cursor:'pointer',
    }}>{children}</button>
  );
}

function MapScreenV3() {
  return (
    <PhoneShell>
      <div style={{ height: '100%', display:'flex', flexDirection:'column', background:'var(--bg)', position: 'relative' }}>

        <div style={{ flex: 1, position: 'relative', overflow: 'hidden' }}>
          <TopoMapV3/>

          {/* Compass top-right (existant, conservé) */}
          <div style={{
            position:'absolute', top: 12, right: 12,
            width: 40, height: 40, borderRadius: 12,
            background: '#0D1626',
            display:'flex', alignItems:'center', justifyContent:'center',
            boxShadow: '0 4px 14px -2px rgba(10,15,26,0.4)',
            zIndex: 20,
          }}>
            <svg width="16" height="16" viewBox="0 0 16 16"><path d="M 8 2 L 11 11 L 8 9 L 5 11 Z" fill="#F26B2E"/></svg>
          </div>

          {/* "Rechercher dans cette zone" — n'apparaît qu'après déplacement */}
          <div style={{
            position: 'absolute', top: 14, left: '50%', transform: 'translateX(-50%)',
            background: 'var(--orange)',
            color: '#FFF',
            padding: '9px 18px 9px 14px',
            borderRadius: 999,
            fontSize: 12.5, fontWeight: 700,
            boxShadow: '0 6px 18px -4px rgba(242,107,46,0.5)',
            display: 'inline-flex', alignItems:'center', gap: 6,
            zIndex: 15, cursor: 'pointer',
          }}>
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#FFF" strokeWidth="2.5" strokeLinecap="round"><polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/></svg>
            Rechercher dans cette zone
          </div>

          {/* PINS — pattern existant (goutte blanche + badge vert/rouge) */}
          <ExistingPin top="180px" left="70px"  sport="🪂" count={1}/>
          <ExistingPin top="140px" left="320px" sport="🏃" count={1}/>
          <ExistingPin top="260px" left="180px" sport="🧗" count={2}/>
          <ExistingPin top="410px" left="100px" sport="🥾" count={4} full/>
          <ExistingPin top="440px" left="280px" sport="🌊" count={1}/>
          <ClusterV3 top="360px" left="210px" count="2"/>

          {/* Right-side — boutons CARRÉS arrondis (la nouveauté) */}
          <div style={{
            position:'absolute', right: 14, bottom: 170,
            display:'flex', flexDirection:'column', gap: 8,
            zIndex: 15,
          }}>
            <SquareBtn>
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#0D1626" strokeWidth="2" strokeLinecap="round"><line x1="4" y1="21" x2="4" y2="14"/><line x1="4" y1="10" x2="4" y2="3"/><line x1="12" y1="21" x2="12" y2="12"/><line x1="12" y1="8" x2="12" y2="3"/><line x1="20" y1="21" x2="20" y2="16"/><line x1="20" y1="12" x2="20" y2="3"/><line x1="1" y1="14" x2="7" y2="14"/><line x1="9" y1="8" x2="15" y2="8"/><line x1="17" y1="16" x2="23" y2="16"/></svg>
            </SquareBtn>
            <SquareBtn>
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#4B7CB8" strokeWidth="2.2" strokeLinecap="round"><circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="3" fill="#4B7CB8"/><line x1="12" y1="2" x2="12" y2="5"/><line x1="12" y1="19" x2="12" y2="22"/><line x1="2" y1="12" x2="5" y2="12"/><line x1="19" y1="12" x2="22" y2="12"/></svg>
            </SquareBtn>
          </div>

          {/* FAB Créer — CARRÉ arrondi plus gros */}
          <div style={{
            position:'absolute', right: 14, bottom: 110,
            zIndex: 18,
          }}>
            <SquareBtn size={58} variant="primary" big>
              <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#FFF" strokeWidth="2.6" strokeLinecap="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
            </SquareBtn>
          </div>
        </div>

        {/* DRAWER REMANIÉ — titre gros, grip visible, CTA explicite */}
        <div style={{
          background: 'var(--bg)',
          borderRadius: '20px 20px 0 0',
          marginTop: -22,
          padding: '10px 18px 12px',
          position: 'relative',
          zIndex: 16,
          boxShadow: '0 -8px 24px -4px rgba(10,15,26,0.5)',
          borderTop: '1px solid var(--line)',
          flexShrink: 0,
        }}>
          <div style={{ width: 48, height: 4.5, borderRadius: 3, background: 'var(--text-dim)', margin: '0 auto 12px', opacity: 0.7 }}/>
          <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between' }}>
            <div className="display" style={{ fontSize: 18, fontWeight: 800, color:'var(--text)', letterSpacing:'-0.02em' }}>
              7 résultats
            </div>
            <div style={{
              display:'flex', alignItems:'center', gap: 6,
              background:'var(--panel)',
              padding:'7px 12px', borderRadius: 999,
              border: '1px solid var(--line)',
              cursor: 'pointer',
            }}>
              <span className="mono" style={{ fontSize: 11, color: 'var(--orange)', fontWeight: 700, textTransform:'uppercase', letterSpacing:'0.1em' }}>
                Voir la liste
              </span>
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#F26B2E" strokeWidth="2.5" strokeLinecap="round"><polyline points="18 15 12 9 6 15"/></svg>
            </div>
          </div>
        </div>

        <AppBottomNav active="map"/>
      </div>
    </PhoneShell>
  );
}

Object.assign(window, { MapScreenV3 });
