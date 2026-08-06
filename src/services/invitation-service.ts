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
  // Emission (00357/00365): the real invitation-to-join (creator-only, server-
  // gated eligibility, cap 20/call + 30/day, message ≤ 500). RETURNS VOID —
  // ineligible/blocked/dup targets are skipped silently, no observable count.
  sendInvitations: async (activityId: string, userIds: string[], message?: string | null): Promise<void> => {
    const { error } = await supabase.rpc('send_activity_invitations', {
      p_activity_id: activityId,
      p_user_ids: userIds,
      p_message: message?.trim() ? message.trim() : undefined,
    });
    if (error) throw error;
  },

  // Reception side of the invitation mirror (00357): my `invited` rows,
  // joined to the activity + inviter.
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
