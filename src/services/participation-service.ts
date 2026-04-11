import { supabase } from './supabase';

export interface Participation {
  id: string;
  activity_id: string;
  user_id: string;
  status: string;
  created_at: string;
  left_at: string | null;
}

export const participationService = {
  join: async (activityId: string): Promise<string> => {
    const { data, error } = await supabase.rpc('join_activity', {
      p_activity_id: activityId,
    });
    if (error) throw error;
    return data as string;
  },

  accept: async (participationId: string): Promise<void> => {
    const { error } = await supabase.rpc('accept_participation', {
      p_participation_id: participationId,
    });
    if (error) throw error;
  },

  refuse: async (participationId: string): Promise<void> => {
    const { error } = await supabase.rpc('refuse_participation', {
      p_participation_id: participationId,
    });
    if (error) throw error;
  },

  leave: async (activityId: string): Promise<void> => {
    const { error } = await supabase.rpc('leave_activity', {
      p_activity_id: activityId,
    });
    if (error) throw error;
  },

  remove: async (participationId: string): Promise<void> => {
    const { error } = await supabase.rpc('remove_participant', {
      p_participation_id: participationId,
    });
    if (error) throw error;
  },

  cancel: async (activityId: string): Promise<void> => {
    const { error } = await supabase.rpc('cancel_activity', {
      p_activity_id: activityId,
    });
    if (error) throw error;
  },

  getMyStatus: async (activityId: string): Promise<Participation | null> => {
    const userId = (await supabase.auth.getUser()).data.user?.id;
    if (!userId) return null;

    const { data, error } = await supabase
      .from('participations')
      .select('id, activity_id, user_id, status, created_at, left_at')
      .eq('activity_id', activityId)
      .eq('user_id', userId)
      .maybeSingle();
    if (error) throw error;
    return data;
  },

  getForActivity: async (activityId: string): Promise<(Participation & { display_name: string; avatar_url: string | null })[]> => {
    const { data, error } = await supabase
      .from('participations')
      .select('id, activity_id, user_id, status, created_at, left_at')
      .eq('activity_id', activityId)
      .order('created_at');
    if (error) throw error;

    // Enrich with user info from public_profiles
    const userIds = (data ?? []).map((p) => p.user_id);
    const { data: profiles } = await supabase
      .from('public_profiles')
      .select('id, display_name, avatar_url')
      .in('id', userIds);

    const profileMap = new Map((profiles ?? []).map((p) => [p.id, p]));

    return (data ?? []).map((p) => ({
      ...p,
      display_name: profileMap.get(p.user_id)?.display_name ?? 'Unknown',
      avatar_url: profileMap.get(p.user_id)?.avatar_url ?? null,
    }));
  },
};
