import { OpenAppLink } from '../../open-app-link';

const APK_DOWNLOAD_URL = process.env.NEXT_PUBLIC_APK_DOWNLOAD_URL ?? '#';

export default function EmailVerifiedPage() {
  return (
    <main style={{
      minHeight: '100vh',
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      padding: 24,
      maxWidth: 480,
      margin: '0 auto',
      textAlign: 'center',
    }}>
      <div style={{
        width: 88,
        height: 88,
        borderRadius: 44,
        background: 'rgba(46, 204, 113, 0.2)',
        border: '2px solid var(--success)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        marginBottom: 24,
        fontSize: 44,
      }}>
        ✓
      </div>

      <h1 style={{ fontSize: 28, fontWeight: 800, marginBottom: 12 }}>
        Email confirmé !
      </h1>
      <p style={{ color: 'var(--text-secondary)', fontSize: 16, lineHeight: 1.5, marginBottom: 32 }}>
        Ton compte Junto est prêt. Ouvre l'app pour te connecter et commencer à explorer.
      </p>

      <OpenAppLink deepLink="junto://" />

      <a
        href={APK_DOWNLOAD_URL}
        style={{ marginTop: 16, color: 'var(--cta)', fontSize: 14, textDecoration: 'underline' }}
      >
        Pas encore Junto installé ? Télécharger
      </a>
    </main>
  );
}
