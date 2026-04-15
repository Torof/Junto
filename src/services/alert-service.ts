import { supabase } from './supabase';

export interface ActivityAlert {
  id: string;
  user_id: string;
  sport_key: string | null;
  radius_km: number;
  levels: string[] | null;
  starts_on: string | null;
  ends_on: string | null;
  created_at: string;
  lng: number;
  lat: number;
}

export const alertService = {
  getAll: async (): Promise<ActivityAlert[]> => {
    const { data, error } = await supabase
      .from('activity_alerts' as 'users')
      .select('id, user_id, sport_key, radius_km, levels, starts_on, ends_on, created_at')
      .order('created_at', { ascending: false }) as unknown as { data: ActivityAlert[] | null; error: Error | null };
    if (error) throw error;
    return data ?? [];
  },

  create: async (
    lng: number,
    lat: number,
    radiusKm: number,
    sportKey?: string,
    levels?: string[],
    startsOn?: string,
    endsOn?: string,
  ): Promise<string> => {
    const { data, error } = await supabase.rpc('create_alert' as 'join_activity', {
      p_lng: lng,
      p_lat: lat,
      p_radius_km: radiusKm,
      p_sport_key: sportKey ?? null,
      p_levels: levels && levels.length > 0 ? levels : null,
      p_starts_on: startsOn ?? null,
      p_ends_on: endsOn ?? null,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
    return data as unknown as string;
  },

  delete: async (alertId: string): Promise<void> => {
    const { error } = await supabase
      .from('activity_alerts' as 'users')
      .delete()
      .eq('id', alertId);
    if (error) throw error;
  },
};
