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
}

export interface ActivityGearItem {
  id: string;
  activity_id: string;
  user_id: string;
  gear_name: string;
  quantity: number;
}

export interface ActivityGearWithProfile extends ActivityGearItem {
  display_name: string;
  avatar_url: string | null;
}

export const gearService = {
  getCatalog: async (sportKey: string): Promise<GearCatalogItem[]> => {
    const { data, error } = await supabase
      .from('gear_catalog' as 'sports')
      .select('id, name_key, sport_keys, display_order, category_key, per_person, shared_recommended_qty')
      .contains('sport_keys' as 'key', [sportKey])
      .order('display_order' as 'key') as unknown as { data: GearCatalogItem[] | null; error: Error | null };
    if (error) return [];
    return data ?? [];
  },

  getForActivity: async (activityId: string): Promise<ActivityGearWithProfile[]> => {
    const { data, error } = await supabase
      .from('activity_gear' as 'sports')
      .select('id, activity_id, user_id, gear_name, quantity')
      .eq('activity_id' as 'key', activityId)
      .order('gear_name' as 'key') as unknown as { data: ActivityGearItem[] | null; error: Error | null };
    if (error) return [];
    if (!data || data.length === 0) return [];

    const userIds = [...new Set(data.map((g) => g.user_id))];
    const { data: profiles } = await supabase
      .from('public_profiles')
      .select('id, display_name, avatar_url')
      .in('id', userIds);
    const profileMap = new Map((profiles ?? []).map((p) => [p.id, p]));

    return data.map((g) => ({
      ...g,
      display_name: profileMap.get(g.user_id)?.display_name ?? '?',
      avatar_url: profileMap.get(g.user_id)?.avatar_url ?? null,
    }));
  },

  setGear: async (activityId: string, items: { name: string; quantity: number }[]): Promise<void> => {
    const { error } = await supabase.rpc('set_activity_gear' as 'join_activity', {
      p_activity_id: activityId,
      p_items: items,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },
};
