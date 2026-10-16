import { create } from 'zustand';

// A one-line notice drawn ON the map (see components/map-toast.tsx). Native
// toasts land at the very bottom of the screen, over the white tab bar, where
// nobody looks (Scott 2026-10-16); this one sits in the lower part of the
// map, above the drawer handle. `nonce` lets the same message re-trigger.
interface MapToastStore {
  message: string | null;
  nonce: number;
  show: (message: string) => void;
}

export const useMapToastStore = create<MapToastStore>((set) => ({
  message: null,
  nonce: 0,
  show: (message) => set((s) => ({ message, nonce: s.nonce + 1 })),
}));

export const showMapToast = (message: string) => useMapToastStore.getState().show(message);
