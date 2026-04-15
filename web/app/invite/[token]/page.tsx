import { OpenAppLink } from '../../open-app-link';

const APK_DOWNLOAD_URL = process.env.NEXT_PUBLIC_APK_DOWNLOAD_URL ?? '#';

export default async function InvitePage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  return (
    <main style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: 24, maxWidth: 480, margin: '0 auto', textAlign: 'center' }}>
      <div style={{ fontSize: 56, marginBottom: 16 }}>🔗</div>
      <h1 style={{ fontSize: 24, fontWeight: 700, marginBottom: 8 }}>Tu as une invitation Junto</h1>
      <p style={{ color: 'var(--text-secondary)', marginBottom: 24, lineHeight: 1.5 }}>
        Ouvre l'app pour rejoindre cette activité privée.
      </p>

      <OpenAppLink deepLink={`junto://invite/${token}`} />

      <a href={APK_DOWNLOAD_URL} style={{ marginTop: 12, color: 'var(--cta)', fontSize: 14, textDecoration: 'underline' }}>
        Pas encore Junto ? Télécharger
      </a>
    </main>
  );
}
