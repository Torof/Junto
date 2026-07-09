import { supabase } from './supabase';

export type GearCategoryKey = 'safety' | 'technical' | 'water' | 'personal';

export interface GearCatalogItem {
  id: string;
  name_key: string;
  sport_keys: string[];
  display_order: number;
  category_key: GearCategoryKey;
  per_person: boolean;
  shared_recommended_qty: number | null;
  // Personal (each user packs their own — helmet, harness) vs shared
  // (group brings one — rope, dry bag). Drives where the item shows
  // up in the gear tab (common inventory vs personal lists only).
  is_shared: boolean;
}

export interface ActivityGearItem {
  id: string;
  activity_id: string;
  user_id: string;
  gear_name: string;
  quantity: number;
  is_shared: boolean;
}

export interface ActivityGearWithProfile extends ActivityGearItem {
  display_name: string;
  avatar_url: string | null;
}


export interface MissingGearItem {
  id: string;
  name: string;
  quantity: number;
  created_by: string | null;
}

export const gearService = {
  getCatalog: async (sportKey: string): Promise<GearCatalogItem[]> => {
    const { data, error } = await supabase
      .from('gear_catalog')
      .select('id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty, is_shared')
      .contains('sport_keys', [sportKey])
      .order('display_order');
    if (error) return [];
    return (data ?? []) as GearCatalogItem[];
  },

  getForActivity: async (activityId: string): Promise<ActivityGearWithProfile[]> => {
    const { data, error } = await supabase
      .from('activity_gear')
      .select('id, activity_id, user_id, gear_name, quantity, is_shared')
      .eq('activity_id', activityId)
      .order('gear_name');
    if (error) return [];
    if (!data || data.length === 0) return [];

    const userIds = new Set<string>();
    data.forEach((g) => userIds.add(g.user_id));
    const { data: profiles } = await supabase
      .from('public_profiles')
      .select('id, display_name, avatar_url')
      .in('id', [...userIds]);
    const profileMap = new Map((profiles ?? []).map((p) => [p.id, p]));

    return data.map((g) => ({
      ...g,
      display_name: profileMap.get(g.user_id)?.display_name ?? '?',
      avatar_url: profileMap.get(g.user_id)?.avatar_url ?? null,
    }));
  },

  setGear: async (
    activityId: string,
    items: { name: string; quantity: number; is_shared?: boolean }[],
  ): Promise<void> => {
    const { error } = await supabase.rpc('set_activity_gear', {
      p_activity_id: activityId,
      p_items: items,
    });
    if (error) throw error;
  },

  // --- "Manquant" tiles (mig 00303) — collaborative missing-gear statements.
  getMissing: async (activityId: string): Promise<MissingGearItem[]> => {
    const { data, error } = await supabase
      .from('activity_gear_missing' as 'activity_gear')
      .select('id, name, quantity, created_by')
      .eq('activity_id', activityId)
      .order('created_at' as 'gear_name') as unknown as { data: MissingGearItem[] | null; error: Error | null };
    if (error) return [];
    return data ?? [];
  },

  addMissing: async (activityId: string, name: string, quantity: number): Promise<void> => {
    const { error } = await supabase.rpc('add_missing_gear' as 'join_activity', {
      p_activity_id: activityId,
      p_name: name,
      p_quantity: quantity,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },

  removeMissing: async (activityId: string, name: string): Promise<void> => {
    const { error } = await supabase.rpc('remove_missing_gear' as 'join_activity', {
      p_activity_id: activityId,
      p_name: name,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },
};
