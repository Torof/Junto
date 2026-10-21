import { supabase } from './supabase';

export const reliabilityService = {
  confirmPresenceViaGeo: async (activityId: string, lng: number, lat: number): Promise<void> => {
    const { error } = await supabase.rpc('confirm_presence_via_geo', {
      p_activity_id: activityId,
      p_lng: lng,
      p_lat: lat,
    });
    if (error) throw error;
  },

  confirmPresenceViaToken: async (token: string): Promise<string> => {
    const { data, error } = await supabase.rpc('confirm_presence_via_token', {
      p_token: token,
    });
    if (error) throw error;
    return data;
  },

  createPresenceToken: async (activityId: string): Promise<string> => {
    const { data, error } = await supabase.rpc('create_presence_token', {
      p_activity_id: activityId,
    });
    if (error) throw error;
    return data;
  },
};
