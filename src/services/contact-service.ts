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
    const { data, error } = await supabase.rpc('get_contacts');
    if (error) throw error;
    return data ?? [];
  },

  getRecentPartners: async (): Promise<PartnerRow[]> => {
    const { data, error } = await supabase.rpc('get_recent_partners');
    if (error) throw error;
    return data ?? [];
  },

  // My current QR token (2-minute validity, refreshed every minute — migs 00456, 00469). The QR encodes it so a
  // scan connects instantly; the shared link never carries it.
  createQrToken: async (): Promise<string> => {
    const { data, error } = await supabase.rpc('create_contact_qr_token');
    if (error) throw error;
    return data;
  },

  // Scanner side: opens (or activates) the DM with the token's owner. Returns
  // the conversation id, or null when the token is unknown / expired / not the
  // owner printed in the QR (mig 00469 — failures return NULL so they count in
  // the scan quota). Throws only on auth / rate limit.
  connectViaQrToken: async (token: string, expectedOwner: string): Promise<string | null> => {
    const { data, error } = await supabase.rpc('connect_via_qr_token',
      { p_token: token, p_expected_owner: expectedOwner });
    if (error) throw error;
    return data ?? null;
  },

  // Owner side: kills every live QR token when « Mon QR Junto » closes, so a
  // screenshot relayed elsewhere is already dead (mig 00469).
  revokeQrTokens: async (token: string): Promise<void> => {
    const { error } = await supabase.rpc('revoke_contact_qr_tokens',
      { p_token: token });
    if (error) throw error;
  },

  // Ends a mutual connection — deletes the shared DM (symmetric; re-requestable).
  removeConnection: async (userId: string): Promise<void> => {
    const { error } = await supabase.rpc('remove_connection', { p_other_user_id: userId });
    if (error) throw error;
  },

};
