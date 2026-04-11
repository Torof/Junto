import { create } from 'zustand';

type ViewMode = 'map' | 'list';

interface MapStore {
  viewMode: ViewMode;
  setViewMode: (mode: ViewMode) => void;
  toggleViewMode: () => void;
}

export const useMapStore = create<MapStore>((set) => ({
  viewMode: 'map',
  setViewMode: (mode) => set({ viewMode: mode }),
  toggleViewMode: () =>
    set((state) => ({ viewMode: state.viewMode === 'map' ? 'list' : 'map' })),
}));
