import { supabase } from './supabase';

export interface NearbyActivity {
  id: string;
  title: string;
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
}

export const activityService = {
  getNearby: async (): Promise<NearbyActivity[]> => {
    const { data, error } = await supabase
      .from('activities_with_coords')
      .select('id, title, level, max_participants, starts_at, duration, status, visibility, sport_id, creator_id, lng, lat')
      .in('status', ['published', 'in_progress'])
      .is('deleted_at', null);
    if (error) throw error;
    return (data ?? []) as NearbyActivity[];
  },
};
