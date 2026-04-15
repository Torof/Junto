// Landing page — front door for new testers

const APK_DOWNLOAD_URL = process.env.NEXT_PUBLIC_APK_DOWNLOAD_URL ?? '#';

export default function Home() {
  return (
    <main style={{
      minHeight: '100vh',
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      padding: '24px',
      textAlign: 'center',
      maxWidth: '720px',
      margin: '0 auto',
    }}>
      <div style={{ width: 96, height: 96, borderRadius: 24, background: 'var(--cta)', display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 32, fontSize: 48 }}>
        🏔️
      </div>

      <h1 style={{ fontSize: 'clamp(28px, 6vw, 44px)', fontWeight: 800, marginBottom: 12 }}>
        Junto
      </h1>

      <p style={{ fontSize: 'clamp(16px, 3vw, 20px)', color: 'var(--text-secondary)', maxWidth: 480, lineHeight: 1.5, marginBottom: 40 }}>
        Trouve des partenaires d'activités outdoor près de chez toi.
        <br />
        Escalade, rando, parapente, canyon, ski de rando…
      </p>

      <a
        href={APK_DOWNLOAD_URL}
        style={{
          display: 'inline-block',
          background: 'var(--cta)',
          color: 'var(--text)',
          padding: '16px 32px',
          borderRadius: 999,
          fontSize: 18,
          fontWeight: 700,
          marginBottom: 16,
        }}
      >
        Télécharger Junto (Android)
      </a>
      <p style={{ color: 'var(--text-secondary)', fontSize: 14, maxWidth: 380 }}>
        Beta privée · iOS bientôt disponible.
      </p>

      <div style={{ marginTop: 64, display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: 24, width: '100%', maxWidth: 640 }}>
        <Feature icon="📍" title="Géolocalisé" body="Vois en un coup d'œil les activités autour de toi." />
        <Feature icon="🔔" title="Alertes perso" body="Reçois une notif dès qu'une activité matche tes critères." />
        <Feature icon="🤝" title="Confiance" body="Score de fiabilité, présence vérifiée, badges réputation." />
      </div>

      <footer style={{ marginTop: 80, color: 'var(--text-secondary)', fontSize: 12 }}>
        © Junto 2026
      </footer>
    </main>
  );
}

function Feature({ icon, title, body }: { icon: string; title: string; body: string }) {
  return (
    <div style={{ background: 'var(--surface-2)', borderRadius: 16, padding: 24, textAlign: 'left' }}>
      <div style={{ fontSize: 28, marginBottom: 8 }}>{icon}</div>
      <div style={{ fontSize: 16, fontWeight: 700, marginBottom: 4 }}>{title}</div>
      <div style={{ fontSize: 14, color: 'var(--text-secondary)', lineHeight: 1.4 }}>{body}</div>
    </div>
  );
}
