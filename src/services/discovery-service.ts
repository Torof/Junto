import { supabase } from './supabase';

export type TransportMode = 'car' | 'motorbike' | 'bike' | 'on_foot' | 'public_transport';
export type DispoIntent = 'discovery' | 'progression' | 'performance' | 'detente' | 'conviviality';
export const DISPO_INTENTS: DispoIntent[] = ['discovery', 'progression', 'performance', 'detente', 'conviviality'];

export interface DispoDraft {
  sportKeys: string[];              // 1–3
  levels: Record<string, string>;   // per-sport grade, may be empty
  intent: DispoIntent[];            // "what you're after", 0–5
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
  intent: DispoIntent[] | null;
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
  radius_km: number | null;
  window_start: string;
  window_end: string;
  intent: DispoIntent[] | null;
  distance_km: number;
  sorties_count: number;
}

export interface DispoZone {
  base_lng: number;
  base_lat: number;
  radius_km: number | null;
}

export interface InvitableActivity {
  id: string;
  title: string;
  sport_key: string;
  starts_at: string;
  max_participants: number;
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
      p_intent: d.intent, // 0–5 codes; empty → NULL server-side
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

  // My future activities that match the target's active dispo — feeds the
  // "Inviter" picker. Empty = nothing to invite them to.
  getInvitableActivities: async (targetUserId: string): Promise<InvitableActivity[]> => {
    const { data, error } = await supabase.rpc('get_invitable_activities_for_dispo', {
      p_target_user_id: targetUserId,
    });
    if (error) throw error;
    return (data ?? []) as unknown as InvitableActivity[];
  },

  // Contact request framed around an activity. On accept → connected + invited.
  sendDiscoveryInvite: async (targetUserId: string, activityId: string): Promise<void> => {
    const { error } = await supabase.rpc('send_discovery_invite', {
      p_target_user_id: targetUserId,
      p_activity_id: activityId,
    });
    if (error) throw error;
  },

  // A match's zone (base + radius) for the zone map. Gated server-side: only a
  // user who already matches my active dispo. Empty → not visible.
  getDispoZone: async (targetUserId: string): Promise<DispoZone | null> => {
    const { data, error } = await supabase.rpc('get_dispo_zone', { p_user_id: targetUserId });
    if (error) throw error;
    return ((data ?? [])[0] ?? null) as unknown as DispoZone | null;
  },
};
