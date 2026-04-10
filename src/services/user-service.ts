import { supabase } from './supabase';

export const userService = {
  getOwnProfile: async () => {
    const { data, error } = await supabase
      .from('users')
      .select('id, email, display_name, avatar_url, bio, sports, levels_per_sport, date_of_birth, phone_verified, tier, is_pro_verified, accepted_tos_at, accepted_privacy_at, created_at')
      .single();
    if (error) throw error;
    return data;
  },

  getPublicProfile: async (userId: string) => {
    const { data, error } = await supabase
      .from('public_profiles')
      .select('id, display_name, avatar_url, bio, sports, levels_per_sport, created_at')
      .eq('id', userId)
      .single();
    if (error) throw error;
    return data;
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
};
