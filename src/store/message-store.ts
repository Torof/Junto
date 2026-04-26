import { create } from 'zustand';
import * as SecureStore from 'expo-secure-store';
import type { MessageMetadata } from '@/services/message-service';

const STORAGE_KEY = 'junto_message_read_at';

interface MessageStore {
  readAt: Record<string, string>;
  loaded: boolean;
  loadReadState: () => Promise<void>;
  markConversationRead: (conversationId: string) => void;
  isConversationUnread: (
    conversationId: string,
    lastMessageAt: string | null,
    lastSenderId: string | null,
    lastMessageMetadata: MessageMetadata | null,
    currentUserId: string | undefined,
  ) => boolean;
  markWallRead: (activityId: string) => void;
  getWallReadAt: (activityId: string) => string | null;
}

const wallKey = (activityId: string) => `wall:${activityId}`;

export const useMessageStore = create<MessageStore>((set, get) => ({
  readAt: {},
  loaded: false,

  loadReadState: async () => {
    try {
      const stored = await SecureStore.getItemAsync(STORAGE_KEY);
      if (stored) {
        set({ readAt: JSON.parse(stored), loaded: true });
      } else {
        set({ loaded: true });
      }
    } catch {
      set({ loaded: true });
    }
  },

  markConversationRead: (conversationId) => {
    const updated = { ...get().readAt, [conversationId]: new Date().toISOString() };
    set({ readAt: updated });
    SecureStore.setItemAsync(STORAGE_KEY, JSON.stringify(updated)).catch(() => {});
  },

  isConversationUnread: (conversationId, lastMessageAt, lastSenderId, lastMessageMetadata, currentUserId) => {
    if (!lastMessageAt || !lastSenderId || !currentUserId) return false;
    // System-generated messages (metadata.type set, e.g. seat_accepted, shared_activity)
    // are informational for both sides — show them as unread even for the technical sender.
    const isSystemMsg = !!lastMessageMetadata?.type;
    if (lastSenderId === currentUserId && !isSystemMsg) return false;
    const readTime = get().readAt[conversationId];
    if (!readTime) return true;
    return lastMessageAt > readTime;
  },

  markWallRead: (activityId) => {
    const updated = { ...get().readAt, [wallKey(activityId)]: new Date().toISOString() };
    set({ readAt: updated });
    SecureStore.setItemAsync(STORAGE_KEY, JSON.stringify(updated)).catch(() => {});
  },

  getWallReadAt: (activityId) => {
    return get().readAt[wallKey(activityId)] ?? null;
  },
}));
