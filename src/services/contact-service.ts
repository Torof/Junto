import { supabase } from './supabase';

// Contacts = mutual connections (Brique 5, mig 00371): get_contacts reads active
// DM connections; recent-partner suggestions; remove_connection ends a connection.

export interface ContactRow {
  id: string;
  display_name: string;
  avatar_url: string | null;
  created_at: string;
}

export interface PartnerRow {
  id: string;
  display_name: string;
  avatar_url: string | null;
}

export const contactService = {
  getContacts: async (): Promise<ContactRow[]> => {
    const { data, error } = await supabase.rpc('get_contacts' as 'join_activity',
      {} as unknown as { p_activity_id: string });
    if (error) throw error;
    return (data ?? []) as unknown as ContactRow[];
  },

  getRecentPartners: async (): Promise<PartnerRow[]> => {
    const { data, error } = await supabase.rpc('get_recent_partners' as 'join_activity',
      {} as unknown as { p_activity_id: string });
    if (error) throw error;
    return (data ?? []) as unknown as PartnerRow[];
  },

  // My current QR token (10-minute validity, mig 00456). The QR encodes it so a
  // scan connects instantly; the shared link never carries it.
  createQrToken: async (): Promise<string> => {
    const { data, error } = await supabase.rpc('create_contact_qr_token' as 'join_activity',
      {} as unknown as { p_activity_id: string });
    if (error) throw error;
    return data as unknown as string;
  },

  // Scanner side: opens (or activates) the DM with the token's owner. Returns
  // the conversation id. Throws on an unknown / expired token.
  connectViaQrToken: async (token: string): Promise<string> => {
    const { data, error } = await supabase.rpc('connect_via_qr_token' as 'join_activity',
      { p_token: token } as unknown as { p_activity_id: string });
    if (error) throw error;
    return data as unknown as string;
  },

  // Ends a mutual connection — deletes the shared DM (symmetric; re-requestable).
  removeConnection: async (userId: string): Promise<void> => {
    const { error } = await supabase.rpc('remove_connection', { p_other_user_id: userId });
    if (error) throw error;
  },

  // Returns how many were actually invited (after dedup / skips).
  inviteToActivity: async (activityId: string, userIds: string[]): Promise<number> => {
    const { data, error } = await supabase.rpc('invite_users_to_activity' as 'join_activity',
      { p_activity_id: activityId, p_user_ids: userIds } as unknown as { p_activity_id: string });
    if (error) throw error;
    return (data as unknown as number) ?? 0;
  },
};
