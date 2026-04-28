import { supabase } from './supabase';

export const reliabilityService = {
  confirmPresenceViaGeo: async (activityId: string, lng: number, lat: number): Promise<void> => {
    const { error } = await supabase.rpc('confirm_presence_via_geo' as 'join_activity', {
      p_activity_id: activityId,
      p_lng: lng,
      p_lat: lat,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },

  confirmPresenceViaToken: async (token: string): Promise<string> => {
    const { data, error } = await supabase.rpc('confirm_presence_via_token' as 'join_activity', {
      p_token: token,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
    return data as unknown as string;
  },

  createPresenceToken: async (activityId: string): Promise<string> => {
    const { data, error } = await supabase.rpc('create_presence_token' as 'join_activity', {
      p_activity_id: activityId,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
    return data as unknown as string;
  },
};
