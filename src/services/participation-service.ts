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

  getForActivity: async (activityId: string): Promise<ParticipantInfo[]> => {
    const { data, error } = await supabase
      .from('activity_participants' as 'participations')
      .select('participation_id, activity_id, user_id, status, created_at, left_at, display_name, avatar_url')
      .eq('activity_id', activityId)
      .order('created_at');
    if (error) throw error;
    return (data ?? []) as unknown as ParticipantInfo[];
  },
};
