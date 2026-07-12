import { supabase } from './supabase';
import type { GeoJsonLineString } from './activity-service';

// A saved trace from the user's personal GPX library (table gpx_traces).
// Reads go through owner-only RLS; writes only via the SECURITY DEFINER
// functions (create/rename/delete) — see migration 00320.
export interface GpxTrace {
  id: string;
  name: string;
  geojson: GeoJsonLineString;
  distance_km: number;
  created_at: string;
  updated_at: string;
}

export const gpxTraceService = {
  // Owner's traces, newest first. RLS restricts rows to auth.uid().
  list: async (): Promise<GpxTrace[]> => {
    const { data, error } = await supabase
      .from('gpx_traces' as 'activities_with_coords')
      .select('id, name, geojson, distance_km, created_at, updated_at')
      .order('created_at', { ascending: false });
    if (error) throw error;
    return (data ?? []) as unknown as GpxTrace[];
  },

  // Server validates the geojson (LineString 2..5000 pts), computes distance,
  // enforces name length + the 50-trace quota, and hardcodes user_id.
  create: async (name: string, geojson: GeoJsonLineString): Promise<GpxTrace> => {
    const { data, error } = await supabase.rpc('create_gpx_trace' as 'join_activity', {
      p_name: name,
      p_geojson: geojson,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
    return data as unknown as GpxTrace;
  },

  rename: async (id: string, name: string): Promise<void> => {
    const { error } = await supabase.rpc('rename_gpx_trace' as 'join_activity', {
      p_id: id,
      p_name: name,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },

  remove: async (id: string): Promise<void> => {
    const { error } = await supabase.rpc('delete_gpx_trace' as 'join_activity', {
      p_id: id,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },
};
