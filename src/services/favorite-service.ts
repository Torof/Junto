import { supabase } from './supabase';

export type FavoriteKind = 'activity' | 'offering' | 'pro';

export interface FavoriteRef {
  kind: FavoriteKind;
  ref_id: string;
  created_at: string;
}

export interface FavActivity { id: string; title: string; starts_at: string; sport_key: string; sport_icon: string; }
export interface FavOffering { id: string; title: string; pro_name: string; price_eur: number | null; price_unit: string | null; image_url: string | null; sport_key: string; }
export interface FavPro { user_id: string; display_name: string; tagline: string | null; pin_image_url: string | null; }

export interface FavoritesDetailed {
  activities: FavActivity[];
  offerings: FavOffering[];
  pros: FavPro[];
}

export const favoriteService = {
  getFavorites: async (): Promise<FavoriteRef[]> => {
    const { data, error } = await supabase.rpc('get_favorites' as 'join_activity',
      {} as unknown as { p_activity_id: string });
    if (error) throw error;
    return (data ?? []) as unknown as FavoriteRef[];
  },

  add: async (kind: FavoriteKind, id: string): Promise<void> => {
    const { error } = await supabase.rpc('add_favorite' as 'join_activity',
      { p_kind: kind, p_id: id } as unknown as { p_activity_id: string });
    if (error) throw error;
  },

  remove: async (kind: FavoriteKind, id: string): Promise<void> => {
    const { error } = await supabase.rpc('remove_favorite' as 'join_activity',
      { p_kind: kind, p_id: id } as unknown as { p_activity_id: string });
    if (error) throw error;
  },

  // Full display data per kind, fetched through the existing views so expired /
  // non-visible peer activities (and suspended pros) are filtered out for free.
  getFavoritesDetailed: async (): Promise<FavoritesDetailed> => {
    const refs = await favoriteService.getFavorites();
    const activityIds = refs.filter((r) => r.kind === 'activity').map((r) => r.ref_id);
    const offeringIds = refs.filter((r) => r.kind === 'offering').map((r) => r.ref_id);
    const proIds = refs.filter((r) => r.kind === 'pro').map((r) => r.ref_id);

    const [activities, offerings, pros] = await Promise.all([
      activityIds.length
        ? supabase.from('activities_with_coords').select('id, title, starts_at, sport_key, sport_icon').in('id', activityIds)
        : Promise.resolve({ data: [], error: null }),
      offeringIds.length
        ? supabase.from('pro_offerings_with_coords').select('id, title, pro_name, price_eur, price_unit, image_url, sport_key').in('id', offeringIds)
        : Promise.resolve({ data: [], error: null }),
      proIds.length
        ? supabase.from('pro_profiles').select('user_id, display_name, tagline, pin_image_url').in('user_id', proIds)
        : Promise.resolve({ data: [], error: null }),
    ]);
    if (activities.error) throw activities.error;
    if (offerings.error) throw offerings.error;
    if (pros.error) throw pros.error;

    // Preserve the favourite order (newest first) from refs.
    const order = (ids: string[], key: 'id' | 'user_id', rows: Record<string, unknown>[]) =>
      ids.map((id) => rows.find((r) => r[key] === id)).filter(Boolean) as Record<string, unknown>[];

    return {
      activities: order(activityIds, 'id', (activities.data ?? []) as Record<string, unknown>[]) as unknown as FavActivity[],
      offerings: order(offeringIds, 'id', (offerings.data ?? []) as Record<string, unknown>[]) as unknown as FavOffering[],
      pros: order(proIds, 'user_id', (pros.data ?? []) as Record<string, unknown>[]) as unknown as FavPro[],
    };
  },
};
