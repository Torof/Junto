import { getSupabase } from '@/lib/supabase';
import { OpenAppLink } from '../../../open-app-link';

import { APK_DOWNLOAD_URL } from '@/lib/download';

interface Offering {
  id: string;
  title: string;
  description: string | null;
  level: string;
  location_name: string;
  schedule_text: string | null;
  sport_key: string;
  sport_icon: string | null;
  pro_name: string;
}

// pro_offerings_with_coords is anon-granted (00250) — the offering preview can
// render real data, mirroring the /activity page.
async function fetchOffering(id: string): Promise<Offering | null> {
  const supabase = getSupabase();
  if (!supabase) return null;
  const { data } = await supabase
    .from('pro_offerings_with_coords')
    .select('id, title, description, level, location_name, schedule_text, sport_key, sport_icon, pro_name')
    .eq('id', id)
    .maybeSingle();
  return data as Offering | null;
}

export default async function OfferingPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const offering = await fetchOffering(id);

  if (!offering) {
    return <NotFound />;
  }

  return (
    <main style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', alignItems: 'center', padding: 24, maxWidth: 560, margin: '0 auto' }}>
      <div style={{ fontSize: 56, marginTop: 32, marginBottom: 16 }}>
        {offering.sport_icon ?? '🏔️'}
      </div>
      <div style={{ fontSize: 13, fontWeight: 700, letterSpacing: 1, color: 'var(--text-secondary)', textTransform: 'uppercase', marginBottom: 4 }}>
        Sortie encadrée par un pro
      </div>
      <h1 style={{ fontSize: 28, fontWeight: 800, textAlign: 'center', marginBottom: 8 }}>
        {offering.title}
      </h1>
      <div style={{ color: 'var(--text-secondary)', fontSize: 16, marginBottom: 24 }}>
        proposée par {offering.pro_name}
      </div>

      {offering.description && (
        <p style={{ background: 'var(--surface-2)', borderRadius: 16, padding: 16, fontSize: 14, lineHeight: 1.5, marginBottom: 24, width: '100%' }}>
          {offering.description}
        </p>
      )}

      <div style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'center', gap: 12, fontSize: 14, color: 'var(--text-secondary)', marginBottom: 32 }}>
        <span>🎚️ {offering.level}</span>
        <span>·</span>
        <span>📍 {offering.location_name}</span>
        {offering.schedule_text && (
          <>
            <span>·</span>
            <span>📅 {offering.schedule_text}</span>
          </>
        )}
      </div>

      <OpenAppLink deepLink={`junto://pro/offering/${offering.id}`} />

      <a
        href={APK_DOWNLOAD_URL}
        style={{ marginTop: 12, color: 'var(--cta)', fontSize: 14, textDecoration: 'underline' }}
      >
        Pas encore Junto ? Télécharger
      </a>
    </main>
  );
}

function NotFound() {
  return (
    <main style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: 24 }}>
      <div style={{ fontSize: 48, marginBottom: 16 }}>🔎</div>
      <h1 style={{ fontSize: 24, fontWeight: 700, marginBottom: 8 }}>Activité introuvable</h1>
      <p style={{ color: 'var(--text-secondary)', textAlign: 'center', maxWidth: 360, marginBottom: 24 }}>
        Cette activité n&apos;existe plus. Découvre les autres sorties sur Junto.
      </p>
      <a href={APK_DOWNLOAD_URL} style={{ background: 'var(--cta)', padding: '12px 24px', borderRadius: 999, fontWeight: 700 }}>
        Télécharger Junto
      </a>
    </main>
  );
}
