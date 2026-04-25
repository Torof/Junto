import { supabase } from './supabase';

export interface SportEndorsement {
  sport_key: string;
  net_count: number;
}

export const endorsementService = {
  submit: async (
    targetId: string,
    activityId: string,
    sportKey: string,
    isConfirmation: boolean,
  ): Promise<void> => {
    const { error } = await supabase.rpc('submit_sport_level_endorsement' as 'join_activity', {
      p_target_id: targetId,
      p_activity_id: activityId,
      p_sport_key: sportKey,
      p_is_confirmation: isConfirmation,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },

  getForUser: async (userId: string): Promise<SportEndorsement[]> => {
    const { data, error } = await supabase.rpc('get_user_sport_endorsements' as 'join_activity', {
      p_user_id: userId,
    } as unknown as { p_activity_id: string });
    if (error) return [];
    return (data as unknown as SportEndorsement[]) ?? [];
  },

  getMyVotesForActivity: async (activityId: string): Promise<{ target_id: string; is_confirmation: boolean }[]> => {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return [];
    const query = supabase.from('sport_level_endorsements' as 'users') as unknown as {
      select: (cols: string) => {
        eq: (col: string, val: string) => {
          eq: (col: string, val: string) => Promise<{ data: { target_id: string; is_confirmation: boolean }[] | null; error: Error | null }>;
        };
      };
    };
    const { data, error } = await query
      .select('target_id, is_confirmation')
      .eq('activity_id', activityId)
      .eq('voter_id', user.id);
    if (error) return [];
    return data ?? [];
  },
};
