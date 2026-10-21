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
      .from('activity_alerts')
      .select('id, user_id, sport_key, radius_km, levels, starts_on, ends_on, created_at')
      .order('created_at', { ascending: false });
    if (error) throw error;
    return (data ?? []) as ActivityAlert[];
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
    const { data, error } = await supabase.rpc('create_alert', {
      p_lng: lng,
      p_lat: lat,
      p_radius_km: radiusKm,
      p_sport_key: (sportKey ?? null) as string,
      p_levels: (levels && levels.length > 0 ? levels : null) as string[],
      p_starts_on: (startsOn ?? null) as string,
      p_ends_on: (endsOn ?? null) as string,
    });
    if (error) throw error;
    return data;
  },

  delete: async (alertId: string): Promise<void> => {
    const { error } = await supabase
      .from('activity_alerts')
      .delete()
      .eq('id', alertId);
    if (error) throw error;
  },
};
