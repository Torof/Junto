import { supabase } from './supabase';
import type { MessageMetadata } from './message-service';

export interface Conversation {
  id: string;
  user_1: string;
  user_2: string;
  status: string;
  last_message_at: string | null;
  created_at: string;
  other_user_name: string;
  other_user_avatar: string | null;
  last_message_content: string | null;
  last_message_sender_id: string | null;
  last_message_metadata: MessageMetadata | null;
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
  getAll: async (): Promise<Conversation[]> => {
    const userId = (await supabase.auth.getUser()).data.user?.id;
    if (!userId) return [];

    const { data, error } = await supabase
      .from('conversations' as 'users')
      .select('id, user_1, user_2, status, last_message_at, created_at, hidden_by_user_1, hidden_by_user_2')
      .eq('status' as 'id', 'active')
      .order('last_message_at', { ascending: false, nullsFirst: false }) as unknown as { data: { id: string; user_1: string; user_2: string; status: string; last_message_at: string | null; created_at: string; hidden_by_user_1: boolean; hidden_by_user_2: boolean }[] | null; error: Error | null };
    if (error) throw error;

    if (!data || data.length === 0) return [];

    // Filter out hidden conversations for this user
    const visible = data.filter((c) => {
      if (c.user_1 === userId && c.hidden_by_user_1) return false;
      if (c.user_2 === userId && c.hidden_by_user_2) return false;
      return true;
    });

    if (visible.length === 0) return [];

    const otherUserIds = visible.map((c) =>
      c.user_1 === userId ? c.user_2 : c.user_1
    );
    const { data: profiles } = await supabase
      .from('public_profiles')
      .select('id, display_name, avatar_url')
      .in('id', otherUserIds);

    const profileMap = new Map(
      (profiles ?? []).map((p) => [p.id, p])
    );

    const conversationIds = visible.map((c) => c.id);
    const { data: lastMessages } = await supabase
      .from('private_messages')
      .select('conversation_id, content, sender_id, created_at, metadata')
      .in('conversation_id' as 'id', conversationIds)
      .is('deleted_at', null)
      .order('created_at', { ascending: false }) as unknown as { data: { conversation_id: string; content: string; sender_id: string; created_at: string; metadata: MessageMetadata | null }[] | null };

    const lastMessageMap = new Map<string, { content: string; sender_id: string; metadata: MessageMetadata | null }>();
    for (const msg of lastMessages ?? []) {
      if (!lastMessageMap.has(msg.conversation_id)) {
        lastMessageMap.set(msg.conversation_id, { content: msg.content, sender_id: msg.sender_id, metadata: msg.metadata });
      }
    }

    return visible.map((c) => {
      const otherId = c.user_1 === userId ? c.user_2 : c.user_1;
      const profile = profileMap.get(otherId);
      const lastMsg = lastMessageMap.get(c.id);
      return {
        ...c,
        other_user_name: profile?.display_name ?? '?',
        other_user_avatar: profile?.avatar_url ?? null,
        last_message_content: lastMsg?.content ?? null,
        last_message_sender_id: lastMsg?.sender_id ?? null,
        last_message_metadata: lastMsg?.metadata ?? null,
      };
    });
  },

  getPendingReceived: async (): Promise<PendingRequest[]> => {
    const userId = (await supabase.auth.getUser()).data.user?.id;
    if (!userId) return [];

    const { data, error } = await supabase
      .from('conversations' as 'users')
      .select('id, user_1, user_2, request_sender_id, initiated_from, request_message, created_at, request_expires_at')
      .eq('status' as 'id', 'pending_request')
      .order('created_at', { ascending: false }) as unknown as {
        data: { id: string; user_1: string; user_2: string; request_sender_id: string; initiated_from: string | null; request_message: string | null; created_at: string; request_expires_at: string | null }[] | null;
        error: Error | null;
      };
    if (error) throw error;

    // Filter: only requests where I'm the RECIPIENT (not the sender)
    // and skip rows that have already passed their expiry — the server
    // cleanup runs on activity-transition checks, so there's a small window
    // where stale rows still appear if the user opens the tab before the
    // next transition tick fires.
    const now = Date.now();
    const received = (data ?? []).filter(
      (c) =>
        (c.user_1 === userId || c.user_2 === userId) &&
        c.request_sender_id !== userId
    ).filter((c) => {
      const exp = (c as { request_expires_at?: string | null }).request_expires_at;
      return !exp || new Date(exp).getTime() > now;
    });

    if (received.length === 0) return [];

    const senderIds = received.map((c) => c.request_sender_id);
    const { data: profiles } = await supabase
      .from('public_profiles')
      .select('id, display_name, avatar_url')
      .in('id', senderIds);

    const profileMap = new Map(
      (profiles ?? []).map((p) => [p.id, p])
    );

    return received.map((c) => {
      const profile = profileMap.get(c.request_sender_id);
      return {
        ...c,
        sender_name: profile?.display_name ?? '?',
        sender_avatar: profile?.avatar_url ?? null,
      };
    });
  },

  sendContactRequest: async (targetUserId: string, message: string, source: string = 'profile'): Promise<string> => {
    const { data, error } = await supabase.rpc('send_contact_request' as 'join_activity', {
      p_target_user_id: targetUserId,
      p_message: message,
      p_source: source,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
    return data as unknown as string;
  },

  acceptRequest: async (conversationId: string): Promise<void> => {
    const { error } = await supabase.rpc('accept_contact_request' as 'join_activity', {
      p_conversation_id: conversationId,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },

  declineRequest: async (conversationId: string): Promise<void> => {
    const { error } = await supabase.rpc('decline_contact_request' as 'join_activity', {
      p_conversation_id: conversationId,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },

  cancelRequest: async (conversationId: string): Promise<void> => {
    const { error } = await supabase.rpc('cancel_contact_request' as 'join_activity', {
      p_conversation_id: conversationId,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },

  getConversationStateWith: async (otherUserId: string): Promise<{ id: string; status: string } | null> => {
    const userId = (await supabase.auth.getUser()).data.user?.id;
    if (!userId) return null;
    const u1 = userId < otherUserId ? userId : otherUserId;
    const u2 = userId < otherUserId ? otherUserId : userId;
    const { data } = await supabase
      .from('conversations' as 'users')
      .select('id, status')
      .eq('user_1' as 'id', u1)
      .eq('user_2' as 'id', u2)
      .single() as unknown as { data: { id: string; status: string } | null };
    return data ?? null;
  },

  createOrGet: async (otherUserId: string): Promise<string> => {
    const { data, error } = await supabase.rpc('create_or_get_conversation' as 'join_activity', {
      p_other_user_id: otherUserId,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
    return data as unknown as string;
  },

  hideConversation: async (conversationId: string): Promise<void> => {
    const { error } = await supabase.rpc('hide_conversation' as 'join_activity', {
      p_conversation_id: conversationId,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },

  getUnreadCount: async (): Promise<number> => {
    return 0;
  },
};
