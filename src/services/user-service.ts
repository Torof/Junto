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
  sports_count: number;
  reliability_score: number | null;
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
    const { data, error } = await supabase.rpc('get_user_public_stats' as 'join_activity', {
      p_user_id: userId,
    } as unknown as { p_activity_id: string });
    if (error) return { total_activities: 0, completed_activities: 0, sports_count: 0, reliability_score: null };
    const rows = data as unknown as UserStats[];
    return Array.isArray(rows) && rows.length > 0
      ? rows[0] ?? { total_activities: 0, completed_activities: 0, sports_count: 0, reliability_score: null }
      : { total_activities: 0, completed_activities: 0, sports_count: 0, reliability_score: null };
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
    const { error } = await supabase
      .from('blocked_users')
      .delete()
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
