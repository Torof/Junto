import { supabase } from './supabase';
import type { MessageMetadata } from './message-service';

export type ConversationType = 'dm' | 'group' | 'activity' | 'channel';

export interface Conversation {
  id: string;
  type: ConversationType;
  status: string;
  last_message_at: string | null;
  created_at: string;
  last_message_content: string | null;
  last_message_sender_id: string | null;
  last_message_metadata: MessageMetadata | null;
  is_unread: boolean;
  // DM
  user_1: string | null;
  user_2: string | null;
  other_user_id: string | null;
  other_user_name: string | null;
  other_user_avatar: string | null;
  other_user_reliability_tier: string | null;
  // Groupe
  name: string | null;
  icon: string | null;
  member_count: number | null;
  // Activité
  activity_id: string | null;
  activity_title: string | null;
  sport_id: string | null;
}

export interface PendingRequest {
  id: string;
  user_1: string;
  user_2: string;
  request_sender_id: string;
  initiated_from: string | null;
  request_message: string | null;
  created_at: string;
  sender_name: string;
  sender_avatar: string | null;
}

export const conversationService = {
  // Curated read (00351) — the conversations base table is no longer directly
  // readable by clients (design-review fix: raw `status` leaked the silent
  // decline). The RPC returns active conversations + peer + last message.
  getAll: async (): Promise<Conversation[]> => {
    const { data, error } = await supabase.rpc('get_my_conversations');
    if (error) throw error;
    return (data ?? []).map((c) => ({
      ...c,
      type: c.type as ConversationType,
      last_message_metadata: (c.last_message_metadata ?? null) as MessageMetadata | null,
    }));
  },

  // Unified store (00355): server-side read receipt (own conversation_members
  // row). Drives the hub's is_unread + the tab badge — call on opening a thread.
  markRead: async (conversationId: string): Promise<void> => {
    const { error } = await supabase.rpc('mark_conversation_read', {
      p_conversation_id: conversationId,
    });
    if (error) throw error;
  },

  // Curated read (00351) — recipient-side pending requests; expiry filtered
  // server-side, the expiry column itself is never exposed.
  getPendingReceived: async (): Promise<PendingRequest[]> => {
    const { data, error } = await supabase.rpc('get_pending_contact_requests');
    if (error) throw error;
    return data ?? [];
  },

  sendContactRequest: async (targetUserId: string, message: string, source: string = 'profile'): Promise<string> => {
    const { data, error } = await supabase.rpc('send_contact_request', {
      p_target_user_id: targetUserId,
      p_message: message,
      p_source: source,
    });
    if (error) throw error;
    return data;
  },

  acceptRequest: async (conversationId: string): Promise<void> => {
    const { error } = await supabase.rpc('accept_contact_request', {
      p_conversation_id: conversationId,
    });
    if (error) throw error;
  },

  declineRequest: async (conversationId: string): Promise<void> => {
    const { error } = await supabase.rpc('decline_contact_request', {
      p_conversation_id: conversationId,
    });
    if (error) throw error;
  },

  // Curated read (00351) — returns 'active' | 'pending' | null. 'pending'
  // deliberately merges pending_request and declined (silent decline must be
  // indistinguishable for the sender, at the DB level, not just in the UI).
  getConversationStateWith: async (otherUserId: string): Promise<{ id: string; status: string } | null> => {
    const { data, error } = await supabase.rpc('get_conversation_state_with', {
      p_other_user_id: otherUserId,
    });
    if (error) throw error;
    const row = (data ?? [])[0];
    return row ? { id: row.id, status: row.state } : null;
  },

  // Unified store (00355): per-member hidden_at (the old hide_conversation wrote
  // hidden_by_user_* which the new hub no longer reads).
  hideConversation: async (conversationId: string): Promise<void> => {
    const { error } = await supabase.rpc('set_conversation_hidden', {
      p_conversation_id: conversationId,
      p_hidden: true,
    });
    if (error) throw error;
  },
};
