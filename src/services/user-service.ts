import { supabase } from './supabase';

export interface PublicProfile {
  id: string;
  display_name: string;
  avatar_url: string | null;
  sports: string[];
  levels_per_sport: Record<string, string> | null;
  created_at: string;
}

export interface UserStats {
  total_activities: number;
  completed_activities: number;
  created_activities: number;
  joined_activities: number;
  sports_count: number;
  reliability_score: number | null;
  reliability_tier: string | null;
}

export const userService = {
  getPublicProfile: async (userId: string): Promise<PublicProfile | null> => {
    const { data, error } = await supabase
      .from('public_profiles')
      .select('id, display_name, avatar_url, sports, levels_per_sport, created_at')
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
      reliability_tier: null,
    };
    if (!userId) {
      return empty;
    }
    const { data, error } = await supabase.rpc('get_user_public_stats' as 'join_activity', {
      p_user_id: userId,
    } as unknown as { p_activity_id: string });
    if (error) {
      return empty;
    }
    const rows = data as unknown as UserStats[];
    if (!Array.isArray(rows) || rows.length === 0) {
      return empty;
    }
    return rows[0] ?? empty;
  },

  updateProfile: async (updates: {
    display_name?: string;
    avatar_url?: string;
    bio?: string;
    sports?: string[];
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

  // The ONLY writer of levels_per_sport (locked server-side). First declaration
  // is free; a change is peer-gated (up requires net ≥ 3) and resets the votes.
  // See set_sport_level (mig 00295).
  setSportLevel: async (sportKey: string, level: string): Promise<void> => {
    const { error } = await supabase.rpc('set_sport_level' as 'join_activity', {
      p_sport_key: sportKey,
      p_new_level: level,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
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
