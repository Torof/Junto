import { OpenAppLink } from '../../open-app-link';

import { APK_DOWNLOAD_URL } from '@/lib/download';

const UUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

export default async function ContactPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  // Untrusted path segment → never splice into a deep-link / intent:// URI unless
  // it is a bare UUID (blocks route-redirection and intent-URI injection).
  if (!UUID_RE.test(id)) {
    return (
      <main style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: 24, maxWidth: 480, margin: '0 auto', textAlign: 'center' }}>
        <div style={{ fontSize: 56, marginBottom: 16 }}>🤷</div>
        <h1 style={{ fontSize: 24, fontWeight: 700, marginBottom: 8 }}>Lien invalide</h1>
        <p style={{ color: 'var(--text-secondary)' }}>Ce lien de contact n&apos;est pas valide.</p>
      </main>
    );
  }
  return (
    <main style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: 24, maxWidth: 480, margin: '0 auto', textAlign: 'center' }}>
      <div style={{ fontSize: 56, marginBottom: 16 }}>🤝</div>
      <h1 style={{ fontSize: 24, fontWeight: 700, marginBottom: 8 }}>Ajoute ce partenaire sur Junto</h1>
      <p style={{ color: 'var(--text-secondary)', marginBottom: 24, lineHeight: 1.5 }}>
        Ouvre l'app pour voir son profil et lui envoyer une demande de contact.
      </p>

      <OpenAppLink deepLink={`junto://profile/${id}`} />

      <a href={APK_DOWNLOAD_URL} style={{ marginTop: 12, color: 'var(--cta)', fontSize: 14, textDecoration: 'underline' }}>
        Pas encore Junto ? Télécharger
      </a>
    </main>
  );
}
