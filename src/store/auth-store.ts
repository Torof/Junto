import { create } from 'zustand';

interface AuthStoreState {
  refreshTick: number;
  triggerRefresh: () => void;
}

export const useAuthStore = create<AuthStoreState>((set) => ({
  refreshTick: 0,
  triggerRefresh: () => set((s) => ({ refreshTick: s.refreshTick + 1 })),
}));
