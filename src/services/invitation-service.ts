import { supabase } from './supabase';

export interface ActivityInvitation {
  activity_id: string;
  activity_title: string;
  sport_id: string;
  starts_at: string;
  invited_by: string | null;
  inviter_name: string | null;
  inviter_avatar: string | null;
  invite_message: string | null;
  invited_at: string;
}

export const invitationService = {
  // Reception side of the invitation mirror (00357): my `invited` rows,
  // joined to the activity + inviter. Emission stays server-gated (creator only).
  getMyInvitations: async (): Promise<ActivityInvitation[]> => {
    const { data, error } = await supabase.rpc('get_my_invitations');
    if (error) throw error;
    return data ?? [];
  },

  // Pre-approved: accept → participant (capacity checked at acceptance, 00365).
  accept: async (activityId: string): Promise<void> => {
    const { error } = await supabase.rpc('accept_activity_invitation', {
      p_activity_id: activityId,
    });
    if (error) throw error;
  },

  // Silent DELETE — never writes refused_at (no 24h cooldown, 00365).
  decline: async (activityId: string): Promise<void> => {
    const { error } = await supabase.rpc('decline_activity_invitation', {
      p_activity_id: activityId,
    });
    if (error) throw error;
  },
};
