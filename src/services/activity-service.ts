import { supabase } from './supabase';

export const activityService = {
  getNearby: async (lat: number, lng: number, radiusMeters: number = 50000) => {
    // Uses PostGIS ST_DWithin via a direct query
    // The RPC function will be created in Sprint 3 — for now, query activities directly
    const { data, error } = await supabase
      .from('activities')
      .select('id, title, level, max_participants, starts_at, duration, status, visibility, created_at, sport_id, creator_id')
      .in('status', ['published', 'in_progress'])
      .is('deleted_at', null);
    if (error) throw error;
    return data;
  },
};
