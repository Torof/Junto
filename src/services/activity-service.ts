import { supabase } from './supabase';

export const activityService = {
  getNearby: async () => {
    const { data, error } = await supabase
      .from('activities')
      .select('id, title, level, max_participants, starts_at, duration, status, visibility, sport_id, creator_id, location_start')
      .in('status', ['published', 'in_progress'])
      .is('deleted_at', null);
    if (error) throw error;
    return data;
  },
};
