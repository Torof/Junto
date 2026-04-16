import { supabase } from './supabase';

export interface PublicProfile {
  id: string;
  display_name: string;
  avatar_url: string | null;
  sports: string[];
  created_at: string;
}

export interface UserStats {
  total_activities: number;
  completed_activities: number;
  created_activities: number;
  joined_activities: number;
  sports_count: number;
  reliability_score: number | null;
}

export interface SportBreakdownRow {
  sport_key: string;
  sport_icon: string;
  level: string | null;
  completed_count: number;
}

export const userService = {
  getOwnProfile: async () => {
    const { data, error } = await supabase
      .from('users')
      .select('id, email, display_name, avatar_url, bio, sports, levels_per_sport, date_of_birth, phone_verified, tier, is_pro_verified, accepted_tos_at, accepted_privacy_at, created_at')
      .single();
    if (error) throw error;
    return data;
  },

  getPublicProfile: async (userId: string): Promise<PublicProfile | null> => {
    const { data, error } = await supabase
      .from('public_profiles')
      .select('id, display_name, avatar_url, sports, created_at')
      .eq('id', userId)
      .single();
    if (error) return null;
    return data as PublicProfile;
  },

  getPublicStats: async (userId: string): Promise<UserStats> => {
    const empty: UserStats = {
      total_activities: 0,
      completed_activities: 0,
      created_activities: 0,
      joined_activities: 0,
      sports_count: 0,
      reliability_score: null,
    };
    if (!userId) {
      console.warn('[getPublicStats] called with empty userId');
      return empty;
    }
    const { data, error } = await supabase.rpc('get_user_public_stats' as 'join_activity', {
      p_user_id: userId,
    } as unknown as { p_activity_id: string });
    if (error) {
      console.warn('[getPublicStats] RPC error', error);
      return empty;
    }
    const rows = data as unknown as UserStats[];
    if (!Array.isArray(rows) || rows.length === 0) {
      console.warn('[getPublicStats] empty response', data);
      return empty;
    }
    return rows[0] ?? empty;
  },

  getSportBreakdown: async (userId: string): Promise<SportBreakdownRow[]> => {
    if (!userId) {
      console.warn('[getSportBreakdown] called with empty userId');
      return [];
    }
    const { data, error } = await supabase.rpc('get_user_sport_breakdown' as 'join_activity', {
      p_user_id: userId,
    } as unknown as { p_activity_id: string });
    if (error) {
      console.warn('[getSportBreakdown] RPC error', error);
      return [];
    }
    return (data as unknown as SportBreakdownRow[]) ?? [];
  },

  updateProfile: async (updates: {
    display_name?: string;
    avatar_url?: string;
    bio?: string;
    sports?: string[];
    levels_per_sport?: Record<string, string>;
  }) => {
    const { data, error } = await supabase
      .from('users')
      .update(updates)
      .eq('id', (await supabase.auth.getUser()).data.user?.id ?? '')
      .select('id, display_name, avatar_url, bio, sports, levels_per_sport')
      .single();
    if (error) throw error;
    return data;
  },

  blockUser: async (blockedId: string): Promise<void> => {
    const { error } = await supabase
      .from('blocked_users')
      .insert({ blocked_id: blockedId, blocker_id: (await supabase.auth.getUser()).data.user?.id ?? '' });
    if (error) throw error;
  },

  unblockUser: async (blockedId: string): Promise<void> => {
    const userId = (await supabase.auth.getUser()).data.user?.id ?? '';
    const { error } = await supabase
      .from('blocked_users')
      .delete()
      .eq('blocker_id', userId)
      .eq('blocked_id', blockedId);
    if (error) throw error;
  },

  isBlocked: async (userId: string): Promise<boolean> => {
    const { count, error } = await supabase
      .from('blocked_users')
      .select('id', { count: 'exact', head: true })
      .eq('blocked_id', userId);
    if (error) return false;
    return (count ?? 0) > 0;
  },
};
