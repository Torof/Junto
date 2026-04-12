import { create } from 'zustand';
import * as SecureStore from 'expo-secure-store';

const STORAGE_KEY = 'junto_message_read_at';

interface MessageStore {
  readAt: Record<string, string>;
  loaded: boolean;
  loadReadState: () => Promise<void>;
  markConversationRead: (conversationId: string) => void;
  isConversationUnread: (conversationId: string, lastMessageAt: string | null, lastSenderId: string | null, currentUserId: string | undefined) => boolean;
}

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

  isConversationUnread: (conversationId, lastMessageAt, lastSenderId, currentUserId) => {
    if (!lastMessageAt || !lastSenderId || !currentUserId) return false;
    if (lastSenderId === currentUserId) return false;
    const readTime = get().readAt[conversationId];
    if (!readTime) return true;
    return lastMessageAt > readTime;
  },
}));
