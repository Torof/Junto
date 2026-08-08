import { supabase } from './supabase';

export type TransportMode = 'car' | 'motorbike' | 'bike' | 'on_foot' | 'public_transport';

export interface DispoDraft {
  sportKeys: string[];              // 1–3
  levels: Record<string, string>;   // per-sport grade, may be empty
  baseLng: number;
  baseLat: number;
  baseLabel: string;
  radiusKm: number | null;          // null = "peu importe"
  transportModes: TransportMode[];  // ≥1
  windowStart: string;              // ISO
  windowEnd: string;                // ISO
}

export interface MyDispo {
  id: string;
  sport_keys: string[];
  levels: Record<string, string> | null;
  base_lng: number;
  base_lat: number;
  base_label: string;
  radius_km: number | null;
  transport_modes: TransportMode[];
  window_start: string;
  window_end: string;
  is_active: boolean;
}

export interface DiscoveryCard {
  user_id: string;
  display_name: string;
  avatar_url: string | null;
  reliability_tier: string | null;
  sport_keys: string[];
  levels: Record<string, string> | null;
  transport_modes: TransportMode[];
  distance_km: number;
  sorties_count: number;
}

// get_discovery_count returns -1 as the "quelques" floor (1–2 matches).
export const DISCOVERY_FEW = -1;

export const discoveryService = {
  getMyDispo: async (): Promise<MyDispo | null> => {
    const { data, error } = await supabase.rpc('get_my_dispo');
    if (error) throw error;
    return ((data ?? [])[0] ?? null) as unknown as MyDispo | null;
  },

  upsert: async (d: DispoDraft): Promise<string> => {
    const { data, error } = await supabase.rpc('upsert_dispo', {
      p_sport_keys: d.sportKeys,
      p_levels: d.levels,
      p_base_lng: d.baseLng,
      p_base_lat: d.baseLat,
      p_base_label: d.baseLabel,
      p_radius_km: d.radiusKm as unknown as number, // DB accepts NULL ("peu importe")
      p_transport_modes: d.transportModes,
      p_window_start: d.windowStart,
      p_window_end: d.windowEnd,
    });
    if (error) throw error;
    return data as string;
  },

  activate: async (): Promise<void> => {
    const { error } = await supabase.rpc('activate_dispo');
    if (error) throw error;
  },

  deactivate: async (): Promise<void> => {
    const { error } = await supabase.rpc('deactivate_dispo');
    if (error) throw error;
  },

  // Live counter during compose. -1 (DISCOVERY_FEW) = "quelques".
  getCount: async (f: {
    sportKeys: string[]; baseLng: number; baseLat: number;
    radiusKm: number | null; windowStart: string; windowEnd: string;
  }): Promise<number> => {
    const { data, error } = await supabase.rpc('get_discovery_count', {
      p_sport_keys: f.sportKeys,
      p_base_lng: f.baseLng,
      p_base_lat: f.baseLat,
      p_radius_km: f.radiusKm as unknown as number, // DB accepts NULL

      p_window_start: f.windowStart,
      p_window_end: f.windowEnd,
    });
    if (error) throw error;
    return (data as number) ?? 0;
  },

  getCards: async (): Promise<DiscoveryCard[]> => {
    const { data, error } = await supabase.rpc('get_discovery_cards');
    if (error) throw error;
    return (data ?? []) as unknown as DiscoveryCard[];
  },
};
