import { supabase } from '@/lib/supabase';
import { OpenAppLink } from '../../open-app-link';

const APK_DOWNLOAD_URL = process.env.NEXT_PUBLIC_APK_DOWNLOAD_URL ?? '#';

interface Activity {
  id: string;
  title: string;
  description: string | null;
  starts_at: string;
  level: string;
  max_participants: number;
  participant_count: number;
  visibility: string;
  sport_key: string;
  sport_icon: string | null;
  creator_name: string;
}

async function fetchActivity(id: string): Promise<Activity | null> {
  const { data } = await supabase
    .from('activities_with_creator')
    .select('id, title, description, starts_at, level, max_participants, participant_count, visibility, sport_key, sport_icon, creator_name')
    .eq('id', id)
    .in('visibility', ['public', 'approval'])
    .maybeSingle();
  return data as Activity | null;
}

function formatDate(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleString('fr-FR', { weekday: 'short', day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' });
}

export default async function ActivityPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const activity = await fetchActivity(id);

  if (!activity) {
    return <NotFound />;
  }

  return (
    <main style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', alignItems: 'center', padding: 24, maxWidth: 560, margin: '0 auto' }}>
      <div style={{ fontSize: 56, marginTop: 32, marginBottom: 16 }}>
        {activity.sport_icon ?? '🏔️'}
      </div>
      <div style={{ fontSize: 14, color: 'var(--text-secondary)', textTransform: 'capitalize', marginBottom: 4 }}>
        {activity.sport_key}
      </div>
      <h1 style={{ fontSize: 28, fontWeight: 800, textAlign: 'center', marginBottom: 8 }}>
        {activity.title}
      </h1>
      <div style={{ color: 'var(--text-secondary)', fontSize: 16, marginBottom: 24 }}>
        {formatDate(activity.starts_at)}
      </div>

      {activity.description && (
        <p style={{ background: 'var(--surface-2)', borderRadius: 16, padding: 16, fontSize: 14, lineHeight: 1.5, marginBottom: 24, width: '100%' }}>
          {activity.description}
        </p>
      )}

      <div style={{ display: 'flex', gap: 12, fontSize: 14, color: 'var(--text-secondary)', marginBottom: 32 }}>
        <span>🎚️ {activity.level}</span>
        <span>·</span>
        <span>👥 {activity.participant_count}/{activity.max_participants}</span>
        <span>·</span>
        <span>par {activity.creator_name}</span>
      </div>

      <OpenAppLink deepLink={`junto://activity/${activity.id}`} />

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
      <div style={{ fontSize: 48, marginBottom: 16 }}>🔒</div>
      <h1 style={{ fontSize: 24, fontWeight: 700, marginBottom: 8 }}>Activité introuvable</h1>
      <p style={{ color: 'var(--text-secondary)', textAlign: 'center', maxWidth: 360, marginBottom: 24 }}>
        Cette activité est privée ou n'existe plus. Pour y accéder, ouvre Junto.
      </p>
      <a href={APK_DOWNLOAD_URL} style={{ background: 'var(--cta)', padding: '12px 24px', borderRadius: 999, fontWeight: 700 }}>
        Télécharger Junto
      </a>
    </main>
  );
}
