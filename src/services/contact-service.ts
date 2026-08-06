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
