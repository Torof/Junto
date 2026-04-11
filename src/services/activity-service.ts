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
  getNearby: async (): Promise<NearbyActivity[]> => {
    const { data, error } = await supabase
      .from('activities_with_coords')
      .select(
        'id, title, description, level, max_participants, starts_at, duration, status, visibility, sport_id, creator_id, lng, lat, creator_name, creator_avatar, sport_key, sport_icon, sport_category, participant_count',
      )
      .in('status', ['published', 'in_progress'])
      .is('deleted_at', null);
    if (error) throw error;
    return (data ?? []) as NearbyActivity[];
  },

  getMyCreated: async (): Promise<NearbyActivity[]> => {
    const userId = (await supabase.auth.getUser()).data.user?.id;
    if (!userId) throw new Error('Not authenticated');

    const { data, error } = await supabase
      .from('activities_with_coords')
      .select(
        'id, title, description, level, max_participants, starts_at, duration, status, visibility, sport_id, creator_id, lng, lat, creator_name, creator_avatar, sport_key, sport_icon, sport_category, participant_count',
      )
      .eq('creator_id', userId)
      .is('deleted_at', null)
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
      p_starts_at: form.starts_at.toISOString(),
      p_duration: durationStr,
      p_visibility: form.visibility,
    });
    if (error) throw error;
    return data as string;
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
};
