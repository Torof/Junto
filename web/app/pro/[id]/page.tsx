import { OpenAppLink } from '../../open-app-link';

import { APK_DOWNLOAD_URL } from '@/lib/download';
import { UUID_RE } from '@/lib/uuid';

// Static teaser — pro_profiles is NOT anon-readable (RLS 00256), so this page
// can't render the storefront's data. It exists so shared getjunto.app/pro/{id}
// links land somewhere useful: relay into the app + install fallback.
export default async function ProPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!UUID_RE.test(id)) {
    return (
      <main style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: 24, maxWidth: 480, margin: '0 auto', textAlign: 'center' }}>
        <div style={{ fontSize: 56, marginBottom: 16 }}>🤷</div>
        <h1 style={{ fontSize: 24, fontWeight: 700, marginBottom: 8 }}>Lien invalide</h1>
        <p style={{ color: 'var(--text-secondary)' }}>Ce lien de page professionnelle n&apos;est pas valide.</p>
      </main>
    );
  }

  return (
    <main style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: 24, maxWidth: 560, margin: '0 auto' }}>
      <div style={{ fontSize: 56, marginBottom: 16 }}>📌</div>
      <h1 style={{ fontSize: 26, fontWeight: 800, textAlign: 'center', marginBottom: 8 }}>
        Une page professionnelle sur askandgo
      </h1>
      <p style={{ color: 'var(--text-secondary)', textAlign: 'center', maxWidth: 380, marginBottom: 32, lineHeight: 1.5 }}>
        Guides, moniteurs et écoles d&apos;outdoor. Ouvre askandgo pour voir cette page, son catalogue et ses avis.
      </p>

      <OpenAppLink deepLink={`junto://pro/${id}`} />

      <a
        href={APK_DOWNLOAD_URL}
        style={{ marginTop: 12, color: 'var(--cta)', fontSize: 14, textDecoration: 'underline' }}
      >
        Pas encore askandgo ? Télécharger
      </a>
    </main>
  );
}
