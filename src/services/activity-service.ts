import { supabase } from './supabase';
import { type ActivityFormData } from '@/types/activity-form';

export interface NearbyActivity {
  id: string;
  title: string;
  description: string | null;
  level: string;
  max_participants: number;
  starts_at: string;
  duration: string;
  status: string;
  visibility: string;
  sport_id: string;
  creator_id: string;
  lng: number;
  lat: number;
  creator_name: string;
  creator_avatar: string | null;
  sport_key: string;
  sport_icon: string;
  sport_category: string;
  participant_count: number;
}

export const activityService = {
  getNearby: async (bounds?: { swLng: number; swLat: number; neLng: number; neLat: number }): Promise<NearbyActivity[]> => {
    let query = supabase
      .from('activities_with_coords')
      .select(
        'id, title, description, level, max_participants, starts_at, duration, status, visibility, sport_id, creator_id, lng, lat, creator_name, creator_avatar, sport_key, sport_icon, sport_category, participant_count',
      )
      .in('status', ['published', 'in_progress'])
      .is('deleted_at', null);

    if (bounds) {
      query = query
        .gte('lng', bounds.swLng)
        .lte('lng', bounds.neLng)
        .gte('lat', bounds.swLat)
        .lte('lat', bounds.neLat);
    }

    const { data, error } = await query;
    if (error) throw error;
    return (data ?? []) as NearbyActivity[];
  },

  getMyCreated: async (): Promise<NearbyActivity[]> => {
    const { data, error } = await supabase
      .from('my_activities' as 'activities_with_coords')
      .select(
        'id, title, description, level, max_participants, starts_at, duration, status, visibility, sport_id, creator_id, lng, lat, creator_name, creator_avatar, sport_key, sport_icon, sport_category, participant_count',
      )
      .order('starts_at', { ascending: false });
    if (error) throw error;
    return (data ?? []) as NearbyActivity[];
  },

  getMyJoined: async (): Promise<NearbyActivity[]> => {
    const { data, error } = await supabase
      .from('my_joined_activities' as 'activities_with_coords')
      .select(
        'id, title, description, level, max_participants, starts_at, duration, status, visibility, sport_id, creator_id, lng, lat, creator_name, creator_avatar, sport_key, sport_icon, sport_category, participant_count',
      )
      .order('starts_at', { ascending: false });
    if (error) throw error;
    return (data ?? []) as NearbyActivity[];
  },

  create: async (form: ActivityFormData): Promise<string> => {
    const durationStr = `${form.duration_hours} hours ${form.duration_minutes} minutes`;

    const { data, error } = await supabase.rpc('create_activity', {
      p_sport_id: form.sport_id,
      p_title: form.title,
      p_description: form.description ?? '',
      p_level: form.level,
      p_max_participants: form.max_participants,
      p_start_lng: form.location_start.lng,
      p_start_lat: form.location_start.lat,
      p_meeting_lng: form.location_meeting?.lng,
      p_meeting_lat: form.location_meeting?.lat,
      p_end_lng: form.location_end?.lng,
      p_end_lat: form.location_end?.lat,
      p_starts_at: form.starts_at.toISOString(),
      p_duration: durationStr,
      p_visibility: form.visibility,
    });
    if (error) throw error;
    return data as string;
  },

  getByInviteToken: async (token: string): Promise<NearbyActivity | null> => {
    const { data, error } = await supabase.rpc('get_activity_by_invite_token' as 'join_activity', {
      p_token: token,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
    const rows = data as unknown as NearbyActivity[];
    return Array.isArray(rows) && rows.length > 0 ? rows[0] ?? null : null;
  },

  getInviteToken: async (activityId: string): Promise<string | null> => {
    const { data, error } = await supabase.rpc('get_own_invite_token' as 'join_activity', {
      p_activity_id: activityId,
    } as unknown as { p_activity_id: string });
    if (error) return null;
    return data as unknown as string | null;
  },

  getById: async (id: string): Promise<NearbyActivity | null> => {
    const { data, error } = await supabase
      .from('activities_with_coords')
      .select(
        'id, title, description, level, max_participants, starts_at, duration, status, visibility, sport_id, creator_id, lng, lat, creator_name, creator_avatar, sport_key, sport_icon, sport_category, participant_count',
      )
      .eq('id', id)
      .single();
    if (error) throw error;
    return data as NearbyActivity | null;
  },

  update: async (activityId: string, fields: {
    title?: string;
    description?: string;
    level?: string;
    max_participants?: number;
    start_lng?: number;
    start_lat?: number;
    meeting_lng?: number;
    meeting_lat?: number;
    starts_at?: string;
    duration?: string;
    visibility?: string;
  }): Promise<void> => {
    const { error } = await supabase.rpc('update_activity' as 'join_activity', {
      p_activity_id: activityId,
      p_title: fields.title ?? null,
      p_description: fields.description ?? null,
      p_level: fields.level ?? null,
      p_max_participants: fields.max_participants ?? null,
      p_start_lng: fields.start_lng ?? null,
      p_start_lat: fields.start_lat ?? null,
      p_meeting_lng: fields.meeting_lng ?? null,
      p_meeting_lat: fields.meeting_lat ?? null,
      p_starts_at: fields.starts_at ?? null,
      p_duration: fields.duration ?? null,
      p_visibility: fields.visibility ?? null,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },
};
