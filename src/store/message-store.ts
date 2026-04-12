import { create } from 'zustand';

interface MessageStore {
  lastSeenAt: string | null;
  markSeen: () => void;
}

export const useMessageStore = create<MessageStore>((set) => ({
  lastSeenAt: null,
  markSeen: () => set({ lastSeenAt: new Date().toISOString() }),
}));
