import { supabase } from './supabase';

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
