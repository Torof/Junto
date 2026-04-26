import { supabase } from './supabase';
import type { GeoJsonLineString } from './activity-service';

export interface MessageMetadata {
  type?: 'seat_accepted' | 'shared_activity' | 'shared_trace';
  activity_id?: string;
  name?: string;
  trace_geojson?: GeoJsonLineString;
}

export interface PrivateMessage {
  id: string;
  conversation_id: string;
  sender_id: string;
  receiver_id: string;
  content: string;
  edited_at: string | null;
  deleted_at: string | null;
  created_at: string;
  metadata: MessageMetadata | null;
}

export const messageService = {
  getMessages: async (conversationId: string): Promise<PrivateMessage[]> => {
    const { data, error } = await supabase
      .from('private_messages')
      .select('id, conversation_id, sender_id, receiver_id, content, edited_at, deleted_at, created_at, metadata')
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

  shareActivity: async (conversationId: string, activityId: string): Promise<string> => {
    const { data, error } = await supabase.rpc('share_activity_message' as 'join_activity', {
      p_conversation_id: conversationId,
      p_activity_id: activityId,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
    return data as unknown as string;
  },

  shareTrace: async (conversationId: string, traceGeojson: GeoJsonLineString, name: string): Promise<string> => {
    const { data, error } = await supabase.rpc('share_trace_message' as 'join_activity', {
      p_conversation_id: conversationId,
      p_trace_geojson: traceGeojson,
      p_name: name,
    } as unknown as { p_activity_id: string });
    if (error) throw error;
    return data as unknown as string;
  },
};
