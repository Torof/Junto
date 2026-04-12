import { supabase } from './supabase';

export interface PrivateMessage {
  id: string;
  conversation_id: string;
  sender_id: string;
  receiver_id: string;
  content: string;
  edited_at: string | null;
  deleted_at: string | null;
  created_at: string;
}

export const messageService = {
  getMessages: async (conversationId: string): Promise<PrivateMessage[]> => {
    const { data, error } = await supabase
      .from('private_messages')
      .select('id, conversation_id, sender_id, receiver_id, content, edited_at, deleted_at, created_at')
      .eq('conversation_id' as 'id', conversationId)
      .is('deleted_at', null)
      .order('created_at', { ascending: true });
    if (error) throw error;
    return (data ?? []) as unknown as PrivateMessage[];
  },

  send: async (conversationId: string, content: string): Promise<string> => {
    const { data, error } = await supabase.rpc('send_private_message' as 'join_activity', {
      p_conversation_id: conversationId,
      p_content: content,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
    return data as unknown as string;
  },

  edit: async (messageId: string, content: string): Promise<void> => {
    const { error } = await supabase.rpc('edit_private_message' as 'join_activity', {
      p_message_id: messageId,
      p_content: content,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },

  deleteMessage: async (messageId: string): Promise<void> => {
    const { error } = await supabase.rpc('edit_private_message' as 'join_activity', {
      p_message_id: messageId,
      p_delete: true,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
  },
};
