import { supabase } from './supabase';

export interface Conversation {
  id: string;
  user_1: string;
  user_2: string;
  last_message_at: string | null;
  created_at: string;
  other_user_name: string;
  other_user_avatar: string | null;
  last_message_content: string | null;
  last_message_sender_id: string | null;
}

export const conversationService = {
  getAll: async (): Promise<Conversation[]> => {
    const userId = (await supabase.auth.getUser()).data.user?.id;
    if (!userId) return [];

    const { data, error } = await supabase
      .from('conversations' as 'users')
      .select('id, user_1, user_2, last_message_at, created_at')
      .order('last_message_at', { ascending: false, nullsFirst: false }) as unknown as { data: { id: string; user_1: string; user_2: string; last_message_at: string | null; created_at: string }[] | null; error: Error | null };
    if (error) throw error;

    if (!data || data.length === 0) return [];

    // Resolve other user profiles
    const otherUserIds = data.map((c) =>
      c.user_1 === userId ? c.user_2 : c.user_1
    );
    const { data: profiles } = await supabase
      .from('public_profiles')
      .select('id, display_name, avatar_url')
      .in('id', otherUserIds);

    const profileMap = new Map(
      (profiles ?? []).map((p) => [p.id, p])
    );

    // Get last message for each conversation
    const conversationIds = data.map((c) => c.id);
    const { data: lastMessages } = await supabase
      .from('private_messages')
      .select('conversation_id, content, sender_id, created_at')
      .in('conversation_id' as 'id', conversationIds)
      .is('deleted_at', null)
      .order('created_at', { ascending: false }) as unknown as { data: { conversation_id: string; content: string; sender_id: string; created_at: string }[] | null };

    const lastMessageMap = new Map<string, { content: string; sender_id: string }>();
    for (const msg of lastMessages ?? []) {
      if (!lastMessageMap.has(msg.conversation_id)) {
        lastMessageMap.set(msg.conversation_id, { content: msg.content, sender_id: msg.sender_id });
      }
    }

    return data.map((c) => {
      const otherId = c.user_1 === userId ? c.user_2 : c.user_1;
      const profile = profileMap.get(otherId);
      const lastMsg = lastMessageMap.get(c.id);
      return {
        ...c,
        other_user_name: profile?.display_name ?? '?',
        other_user_avatar: profile?.avatar_url ?? null,
        last_message_content: lastMsg?.content ?? null,
        last_message_sender_id: lastMsg?.sender_id ?? null,
      };
    });
  },

  createOrGet: async (otherUserId: string): Promise<string> => {
    const { data, error } = await supabase.rpc('create_or_get_conversation' as 'join_activity', {
      p_other_user_id: otherUserId,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
    return data as unknown as string;
  },

  getUnreadCount: async (): Promise<number> => {
    // For now, count conversations with messages newer than last viewed
    // Simple approach: count conversations with last_message_at in the last 24h
    // TODO: implement proper read tracking
    return 0;
  },
};
