import { getSupabase } from '@/lib/supabase';

// Read side of the landing. Everything here is what an ANONYMOUS visitor can
// read through PostgREST with the anon key — the demo curtain and RLS apply,
// so at launch these lists are short: every section degrades to a calm
// empty state rather than bragging (Scott's constraint, 2026-10-06).

export interface OutingRow {
  id: string;
  title: string;
  starts_at: string;
  created_at: string;
  level: string | null;
  level_max: string | null;
  distance_km: number | null;
  elevation_gain_m: number | null;
  max_participants: number | null;
  participant_count: number | null;
  sport_key: string | null;
  sport_category: string | null;
  meeting_name: string | null;
  meeting_locality: string | null;
  creator_name: string | null;
}

export interface OfferRow {
  id: string;
  pro_id: string;
  title: string;
  pro_name: string | null;
  location_name: string | null;
  duration: string | null;
  schedule_text: string | null;
  level: string | null;
  price_eur: number | null;
  price_unit: string | null;
  sport_key: string | null;
  sport_category: string | null;
}

export async function fetchUpcomingOutings(limit = 12): Promise<OutingRow[]> {
  const supabase = getSupabase();
  if (!supabase) return [];
  const { data, error } = await supabase
    .from('activities_with_coords')
    .select(
      'id, title, starts_at, created_at, level, level_max, distance_km, elevation_gain_m, max_participants, participant_count, sport_key, sport_category, meeting_name, meeting_locality, creator_name',
    )
    .eq('status', 'published')
    .eq('visibility', 'public')
    .gt('starts_at', new Date().toISOString())
    .order('starts_at', { ascending: true })
    .limit(limit);
  if (error || !data) return [];
  return data as OutingRow[];
}

export async function fetchOffers(limit = 12): Promise<OfferRow[]> {
  const supabase = getSupabase();
  if (!supabase) return [];
  const { data, error } = await supabase
    .from('pro_offerings_with_coords')
    .select(
      'id, pro_id, title, pro_name, location_name, duration, schedule_text, level, price_eur, price_unit, sport_key, sport_category',
    )
    .order('created_at', { ascending: false })
    .limit(limit);
  if (error || !data) return [];
  return data as OfferRow[];
}

// --- formatting helpers shared by the sections ---

const dayFmt = new Intl.DateTimeFormat('fr-FR', { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'Europe/Paris' });
const timeFmt = new Intl.DateTimeFormat('fr-FR', { hour: 'numeric', minute: '2-digit', timeZone: 'Europe/Paris' });

// « sam. 18 oct. · 9h » / « sam. 18 oct. · 17h30 »
export function formatWhen(iso: string): string {
  const d = new Date(iso);
  const day = dayFmt.format(d).replace(/\.$/, '.');
  const [h, m] = timeFmt.format(d).split(':');
  return `${day} · ${h}h${m === '00' ? '' : m}`;
}

// The card's difficulty line, same rule as the app's formatDifficultySignal.
export function difficultyLabel(o: OutingRow): string {
  const parts: string[] = [];
  if (o.distance_km && o.distance_km > 0) parts.push(`${Number(o.distance_km).toLocaleString('fr-FR')} km`);
  if (o.elevation_gain_m && o.elevation_gain_m > 0) parts.push(`${o.elevation_gain_m.toLocaleString('fr-FR')} m D+`);
  if (parts.length) return parts.join(' · ');
  if (o.level && o.level_max && o.level_max !== o.level) return `${o.level} → ${o.level_max}`;
  return o.level ?? 'tous niveaux';
}

// Postgres interval « 03:00:00 » → « 3 h », « 01:30:00 » → « 1 h 30 ».
export function formatDuration(interval: string | null): string | null {
  if (!interval) return null;
  const m = interval.match(/^(?:(\d+) days? )?(\d{1,2}):(\d{2})/);
  if (!m) return interval;
  const days = Number(m[1] ?? 0);
  const h = Number(m[2]) + days * 24;
  const min = Number(m[3]);
  if (h >= 24 && h % 24 === 0) return `${h / 24} jour${h / 24 > 1 ? 's' : ''}`;
  if (h === 0) return `${min} min`;
  return min ? `${h} h ${String(min).padStart(2, '0')}` : `${h} h`;
}

export function formatPrice(eur: number | null, unit: string | null): string | null {
  if (eur == null) return null;
  const base = `${Number(eur).toLocaleString('fr-FR')} €`;
  if (unit === 'person') return `${base} / pers.`;
  if (unit === 'group') return `${base} / groupe`;
  return base;
}

export function isNew(createdAt: string): boolean {
  return Date.now() - new Date(createdAt).getTime() < 48 * 3600 * 1000;
}

export function initials(name: string | null | undefined): string {
  const parts = (name ?? '').trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '?';
  return parts.slice(0, 2).map((p) => p[0]!.toUpperCase()).join('');
}
