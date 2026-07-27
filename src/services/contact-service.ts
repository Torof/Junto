import { supabase } from './supabase';

// One-way contacts roster + recent-partner suggestions + batch invite.
// Backed by the SECURITY DEFINER functions in migration 00341.

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

  addContact: async (userId: string): Promise<void> => {
    const { error } = await supabase.rpc('add_contact' as 'join_activity',
      { p_contact_id: userId } as unknown as { p_activity_id: string });
    if (error) throw error;
  },

  removeContact: async (userId: string): Promise<void> => {
    const { error } = await supabase.rpc('remove_contact' as 'join_activity',
      { p_contact_id: userId } as unknown as { p_activity_id: string });
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
