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
  confirmed_present?: boolean | null;
  reliability_tier?: string | null;
  sports?: string[];
  levels_per_sport?: Record<string, string> | null;
}

export interface Participation {
  id: string;
  activity_id: string;
  user_id: string;
  status: string;
  created_at: string;
  left_at: string | null;
  confirmed_present: boolean | null;
  /** 00543: « Tu y étais ? » answer on an outing without presence validation. */
  self_presence?: string | null;
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
      p_reason: reason ?? undefined,
    });
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
    });
    if (error) throw error;
  },

  waivePenalty: async (participationId: string): Promise<void> => {
    const { error } = await supabase.rpc('waive_late_cancel_penalty', {
      p_participation_id: participationId,
    });
    if (error) throw error;
  },

  declarePresence: async (activityId: string, present: boolean): Promise<void> => {
    const { error } = await supabase.rpc('declare_my_presence', {
      p_activity_id: activityId,
      p_present: present,
    });
    if (error) throw error;
  },

  getMyStatus: async (activityId: string): Promise<Participation | null> => {
    const userId = (await supabase.auth.getUser()).data.user?.id;
    if (!userId) return null;

    const { data, error } = await supabase
      .from('participations')
      .select('id, activity_id, user_id, status, created_at, left_at, confirmed_present, self_presence')
      .eq('activity_id', activityId)
      .eq('user_id', userId)
      .maybeSingle();
    if (error) throw error;
    return data;
  },

  getForActivity: async (activityId: string): Promise<ParticipantInfo[]> => {
    // Routes through get_activity_participants (mig 00230) so creators
    // and accepted participants both see the full accepted list. Direct
    // SELECT on public_participants only returns the caller's own row
    // because participations RLS is auth.uid() = user_id only.
    const { data, error } = await supabase.rpc('get_activity_participants', {
      p_activity_id: activityId,
    });
    if (error) throw error;
    return (data ?? []).map((r) => ({
      participation_id: r.participation_id,
      activity_id: r.activity_id,
      user_id: r.user_id,
      status: r.status,
      created_at: r.created_at,
      display_name: r.display_name,
      avatar_url: r.avatar_url,
      confirmed_present: r.confirmed_present,
    })) as ParticipantInfo[];
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
    // Creator-only RPC backed by the late_cancels ledger (mig 00478). The old
    // direct read of `participations` was limited by RLS to the caller's own
    // row, so the list was always empty (audit PR-6).
    const { data, error } = await supabase.rpc('get_late_leavers',
      { p_activity_id: activityId });
    if (error) throw error;
    return data ?? [];
  },

  getPendingForActivity: async (activityId: string): Promise<ParticipantInfo[]> => {
    const { data, error } = await supabase
      .from('activity_participants')
      .select('participation_id, activity_id, user_id, status, created_at, display_name, avatar_url, reliability_tier, sports, levels_per_sport')
      .eq('activity_id', activityId)
      .eq('status', 'pending')
      .order('created_at');
    if (error) throw error;
    return (data ?? []) as ParticipantInfo[];
  },
};
