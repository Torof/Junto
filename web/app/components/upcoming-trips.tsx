import { getSupabase } from '@/lib/supabase';
import { NAVY, ORANGE, SectionLabel, TopoLines } from './shared';

// Real upcoming activities from the live database (refresh 2026-06-11 —
// the section previously showed hardcoded demo outings whose dates went
// stale in April). Same card design, live data: next public outings,
// linked to their web preview pages. Page-level ISR (revalidate) keeps
// it fresh. If the DB is unreachable or the map is empty, the section
// hides itself rather than showing fakes.

const ACCENTS = ['#F26B2E', '#4B7CB8', '#2E8B57', '#8A4FBF'];

// FR labels for DB sport keys (mirror of the app's i18n sports block).
const SPORT_FR: Record<string, string> = {
  hiking: 'Randonnée', climbing: 'Escalade', 'ski-touring': 'Ski de rando',
  'trail-running': 'Trail', mountaineering: 'Alpinisme', cycling: 'Vélo',
  'mountain-biking': 'VTT', kayaking: 'Kayak', surfing: 'Surf', sailing: 'Voile',
  paragliding: 'Parapente', skiing: 'Ski', snowboarding: 'Snowboard',
  running: 'Course à pied', swimming: 'Natation', football: 'Football',
  tennis: 'Tennis', volleyball: 'Volleyball', badminton: 'Badminton',
  canyoning: 'Canyoning', diving: 'Plongée', 'stand-up-paddle': 'Stand-up Paddle',
  rafting: 'Rafting', 'ice-climbing': 'Cascade de glace',
  'cross-country-ski': 'Ski de fond', skateboarding: 'Skateboard',
  skydiving: 'Parachutisme', triathlon: 'Triathlon', crossfit: 'CrossFit',
  'rock-fishing': 'Pêche en roche', 'horseback-riding': 'Équitation',
  'via-ferrata': 'Via ferrata', slacklining: 'Slackline',
};

interface TripRow {
  id: string;
  title: string;
  starts_at: string;
  level: string | null;
  max_participants: number | null;
  participant_count: number;
  sport_key: string;
  sport_icon: string | null;
  meeting_name: string | null;
  distance_km: number | null;
  elevation_gain_m: number | null;
}

function formatDate(iso: string): { date: string; time: string } {
  const d = new Date(iso);
  const date = d
    .toLocaleDateString('fr-FR', { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'Europe/Paris' })
    .replace(/\.$/, '');
  const h = d.toLocaleTimeString('fr-FR', { hour: 'numeric', minute: '2-digit', timeZone: 'Europe/Paris' });
  // "09:30" → "9h30", "09:00" → "9h"
  const time = h.replace(/^0/, '').replace(':', 'h').replace(/h00$/, 'h');
  return { date, time };
}

async function fetchTrips(): Promise<TripRow[]> {
  const supabase = getSupabase();
  if (!supabase) return [];
  const { data, error } = await supabase
    .from('activities_with_coords')
    .select(
      'id, title, starts_at, level, max_participants, participant_count, sport_key, sport_icon, meeting_name, distance_km, elevation_gain_m',
    )
    .eq('status', 'published')
    .gt('starts_at', new Date().toISOString())
    .order('starts_at', { ascending: true })
    .limit(4);
  if (error || !data) return [];
  return data as TripRow[];
}

export default async function UpcomingTrips() {
  const trips = await fetchTrips();
  if (trips.length === 0) return null;

  return (
    <section
      id="sorties"
      className="junto-trips"
      style={{
        padding: '140px 40px',
        background: 'var(--cream-soft)',
        position: 'relative',
        overflow: 'hidden',
      }}
    >
      <TopoLines opacity={0.04} color={NAVY} count={10} />
      <div style={{ maxWidth: 1180, margin: '0 auto', position: 'relative' }}>
        <div style={{ marginBottom: 64, maxWidth: 720 }}>
          <SectionLabel>En ce moment sur la carte</SectionLabel>
          <h2
            className="display junto-trips-title"
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
            Des sorties, <span style={{ color: ORANGE }}>en vrai.</span>
          </h2>
        </div>

        <div
          className="junto-trips-grid"
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))',
            gap: 20,
          }}
        >
          {trips.map((t, i) => {
            const accent = ACCENTS[i % ACCENTS.length];
            const { date, time } = formatDate(t.starts_at);
            const sportLabel = SPORT_FR[t.sport_key] ?? t.sport_key;
            const detail =
              t.distance_km != null
                ? `${t.distance_km} km`
                : t.elevation_gain_m != null
                  ? `D+ ${t.elevation_gain_m} m`
                  : null;
            return (
              <a
                key={t.id}
                href={`/activity/${t.id}`}
                className="junto-trips-card"
                style={{
                  background: '#FFF',
                  border: '1px solid var(--line)',
                  borderRadius: 20,
                  padding: 28,
                  display: 'grid',
                  gridTemplateColumns: '64px minmax(0, 1fr) auto',
                  gap: 20,
                  alignItems: 'center',
                  textDecoration: 'none',
                  color: 'inherit',
                }}
              >
                <div
                  className="junto-trips-emoji"
                  style={{
                    width: 64,
                    height: 64,
                    borderRadius: 16,
                    background: accent + '22',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    fontSize: 30,
                  }}
                >
                  {t.sport_icon ?? '🏔️'}
                </div>
                <div style={{ minWidth: 0 }}>
                  <div
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      gap: 10,
                      marginBottom: 6,
                      flexWrap: 'wrap',
                    }}
                  >
                    <span
                      className="mono"
                      style={{
                        fontSize: 11,
                        fontWeight: 600,
                        color: accent,
                        textTransform: 'uppercase',
                        letterSpacing: '0.12em',
                      }}
                    >
                      {sportLabel}
                    </span>
                    {t.level && (
                      <>
                        <span style={{ width: 3, height: 3, borderRadius: '50%', background: 'var(--muted)' }} />
                        <span style={{ fontSize: 13, color: 'var(--muted)' }}>{t.level}</span>
                      </>
                    )}
                    {detail && (
                      <>
                        <span style={{ width: 3, height: 3, borderRadius: '50%', background: 'var(--muted)' }} />
                        <span style={{ fontSize: 13, color: 'var(--muted)' }}>{detail}</span>
                      </>
                    )}
                  </div>
                  <h3
                    className="display junto-trips-card-title"
                    style={{
                      fontSize: 22,
                      margin: '0 0 6px',
                      fontWeight: 800,
                      color: NAVY,
                      letterSpacing: '-0.02em',
                      overflow: 'hidden',
                      textOverflow: 'ellipsis',
                      whiteSpace: 'nowrap',
                    }}
                  >
                    {t.title}
                  </h3>
                  <div style={{ fontSize: 13, color: 'var(--muted)', display: 'flex', gap: 10, flexWrap: 'wrap' }}>
                    <span>{date}</span>
                    <span>·</span>
                    <span>{time}</span>
                    {t.meeting_name && (
                      <>
                        <span>·</span>
                        <span style={{ overflow: 'hidden', textOverflow: 'ellipsis' }}>{t.meeting_name}</span>
                      </>
                    )}
                  </div>
                </div>
                <div style={{ textAlign: 'right' }}>
                  <div
                    className="display"
                    style={{ fontSize: 26, fontWeight: 800, color: NAVY, letterSpacing: '-0.02em' }}
                  >
                    {t.participant_count}
                    {t.max_participants != null ? `/${t.max_participants}` : ''}
                  </div>
                  <div
                    className="mono"
                    style={{
                      fontSize: 10,
                      color: 'var(--muted)',
                      letterSpacing: '0.1em',
                      textTransform: 'uppercase',
                    }}
                  >
                    Partants
                  </div>
                </div>
              </a>
            );
          })}
        </div>
      </div>
    </section>
  );
}
