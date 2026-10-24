import { supabase } from './supabase';
import type { Json } from '@/types/supabase';
import type { GeoJsonLineString } from './activity-service';

export interface MessageMetadata {
  type?: 'seat_accepted' | 'seat_request_pending' | 'shared_activity' | 'shared_trace';
  activity_id?: string;
  // Set on 'seat_request_pending' seed messages so the conversation
  // thread can render inline accept/decline buttons + look up the
  // current status to show "accepted/declined/cancelled" badges
  // after a transition.
  seat_request_id?: string;
  name?: string;
  trace_geojson?: GeoJsonLineString;
}

// Quoted-reply payload — the original message (or a placeholder when
// the original was deleted post-reply). Surfaced inside reply bubbles
// so the chat UI can render a small quote at the top.
export interface ReplySnippet {
  id: string;
  sender_id: string;
  content: string;
  deleted_at: string | null;
}

export interface PrivateMessage {
  id: string;
  conversation_id: string;
  sender_id: string;
  content: string;
  edited_at: string | null;
  deleted_at: string | null;
  created_at: string;
  metadata: MessageMetadata | null;
  reply_to_message_id: string | null;
  reply_to: ReplySnippet | null;
  // One per person (00551), read under RLS with the message — members only,
  // never from someone one is blocked with.
  reactions: MessageReaction[];
}

export interface MessageReaction {
  emoji: string;
  user_id: string;
}

type RawMessageRow = Omit<PrivateMessage, 'reply_to'> & {
  reply_to: ReplySnippet | ReplySnippet[] | null;
};

export const messageService = {
  getMessages: async (conversationId: string): Promise<PrivateMessage[]> => {
    // Unified store (00358): direct RLS read on `messages` (member-gated).
    const { data, error } = await supabase
      .from('messages')
      .select(`
        id, conversation_id, sender_id, content,
        edited_at, deleted_at, created_at, metadata, reply_to_message_id,
        reply_to:reply_to_message_id (id, sender_id, content, deleted_at),
        reactions:message_reactions (emoji, user_id)
      `)
      .eq('conversation_id', conversationId)
      .is('deleted_at', null)
      // Latest 200, served oldest-first for the UI. Hard cap so a long
      // thread doesn't fetch unbounded history (prod audit D).
      .order('created_at', { ascending: false })
      .limit(200);
    if (error) throw error;
    data?.reverse();
    // Supabase types the foreign-key embed as an array even on
    // single-row joins via a self-FK — flatten it.
    return ((data ?? []) as unknown as RawMessageRow[]).map((row) => ({
      ...row,
      reply_to: Array.isArray(row.reply_to) ? (row.reply_to[0] ?? null) : row.reply_to,
      reactions: row.reactions ?? [],
    }));
  },

  // Same emoji again or null removes mine; another emoji replaces it (00551).
  react: async (messageId: string, emoji: string | null): Promise<void> => {
    const { error } = await supabase.rpc('set_message_reaction', {
      p_message_id: messageId,
      p_emoji: emoji as string,
    });
    if (error) throw error;
  },

  send: async (conversationId: string, content: string, replyToMessageId?: string | null): Promise<string> => {
    // Always send p_reply_to_message_id (even as null) so PostgREST
    // routes to the 3-arg overload unambiguously. Sending `undefined`
    // drops the key from JSON, which lets the legacy 2-arg overload
    // match — and Postgres flags the call as ambiguous because the
    // 3-arg version has DEFAULT NULL on its third parameter.
    const { data, error } = await supabase.rpc('send_private_message', {
      p_conversation_id: conversationId,
      p_content: content,
      p_reply_to_message_id: (replyToMessageId ?? null) as string,
      // Regenerated types (00351) declare the param optional (undefined) but we
      // MUST ship an explicit null key for overload routing — see comment above.
    });
    if (error) throw error;
    return data;
  },

  // Unified store (00358): sender-only edit/delete on `messages`.
  edit: async (messageId: string, content: string): Promise<void> => {
    const { error } = await supabase.rpc('edit_message', {
      p_message_id: messageId,
      p_content: content,
    });
    if (error) throw error;
  },

  deleteMessage: async (messageId: string): Promise<void> => {
    const { error } = await supabase.rpc('delete_message', {
      p_message_id: messageId,
    });
    if (error) throw error;
  },

  shareActivity: async (conversationId: string, activityId: string): Promise<string> => {
    const { data, error } = await supabase.rpc('share_activity_message', {
      p_conversation_id: conversationId,
      p_activity_id: activityId,
    });
    if (error) throw error;
    return data;
  },

  shareTrace: async (conversationId: string, traceGeojson: GeoJsonLineString, name: string): Promise<string> => {
    const { data, error } = await supabase.rpc('share_trace_message', {
      p_conversation_id: conversationId,
      p_trace_geojson: traceGeojson as unknown as Json,
      p_name: name,
    });
    if (error) throw error;
    return data;
  },
};
