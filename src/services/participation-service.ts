import { supabase } from './supabase';

export interface ParticipantInfo {
  participation_id: string;
  activity_id: string;
  user_id: string;
  status: string;
  created_at: string;
  left_at: string | null;
  display_name: string;
  avatar_url: string | null;
}

export interface Participation {
  id: string;
  activity_id: string;
  user_id: string;
  status: string;
  created_at: string;
  left_at: string | null;
  confirmed_present: boolean | null;
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

  leave: async (activityId: string, reason?: string): Promise<void> => {
    const { error } = await supabase.rpc('leave_activity', {
      p_activity_id: activityId,
      p_reason: reason ?? null,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },

  remove: async (participationId: string): Promise<void> => {
    const { error } = await supabase.rpc('remove_participant', {
      p_participation_id: participationId,
    });
    if (error) throw error;
  },

  cancel: async (activityId: string, reason: string): Promise<void> => {
    const { error } = await supabase.rpc('cancel_activity', {
      p_activity_id: activityId,
      p_reason: reason,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },

  waivePenalty: async (participationId: string): Promise<void> => {
    const { error } = await supabase.rpc('waive_late_cancel_penalty' as 'join_activity', {
      p_participation_id: participationId,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },

  getMyStatus: async (activityId: string): Promise<Participation | null> => {
    const userId = (await supabase.auth.getUser()).data.user?.id;
    if (!userId) return null;

    const { data, error } = await supabase
      .from('participations')
      .select('id, activity_id, user_id, status, created_at, left_at, confirmed_present')
      .eq('activity_id', activityId)
      .eq('user_id', userId)
      .maybeSingle();
    if (error) throw error;
    return data;
  },

  getForActivity: async (activityId: string): Promise<ParticipantInfo[]> => {
    const { data, error } = await supabase
      .from('public_participants' as 'participations')
      .select('participation_id, activity_id, user_id, status, created_at, display_name, avatar_url')
      .eq('activity_id', activityId)
      .order('created_at');
    if (error) throw error;
    return (data ?? []) as unknown as ParticipantInfo[];
  },

  getLateLeaversForCreator: async (activityId: string): Promise<{
    participation_id: string;
    user_id: string;
    display_name: string;
    avatar_url: string | null;
    left_at: string;
    left_reason: string | null;
    penalty_waived: boolean;
  }[]> => {
    const { data, error } = await supabase
      .from('participations')
      .select('id, user_id, left_at, left_reason, penalty_waived, public_profiles!inner(display_name, avatar_url), activities!inner(starts_at)' as 'id')
      .eq('activity_id', activityId)
      .eq('status' as 'user_id', 'withdrawn')
      .not('left_at' as 'user_id', 'is', null);
    if (error) throw error;
    type Row = {
      id: string;
      user_id: string;
      left_at: string;
      left_reason: string | null;
      penalty_waived: boolean;
      public_profiles: { display_name: string; avatar_url: string | null };
      activities: { starts_at: string };
    };
    const rows = (data ?? []) as unknown as Row[];
    return rows
      .filter((r) => new Date(r.left_at).getTime() > new Date(r.activities.starts_at).getTime() - 12 * 3600 * 1000)
      .map((r) => ({
        participation_id: r.id,
        user_id: r.user_id,
        display_name: r.public_profiles.display_name,
        avatar_url: r.public_profiles.avatar_url,
        left_at: r.left_at,
        left_reason: r.left_reason,
        penalty_waived: r.penalty_waived,
      }));
  },

  getPendingForActivity: async (activityId: string): Promise<ParticipantInfo[]> => {
    const { data, error } = await supabase
      .from('activity_participants' as 'participations')
      .select('participation_id, activity_id, user_id, status, created_at, display_name, avatar_url')
      .eq('activity_id', activityId)
      .eq('status' as 'user_id', 'pending')
      .order('created_at');
    if (error) throw error;
    return (data ?? []) as unknown as ParticipantInfo[];
  },
};
