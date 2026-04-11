import { create } from 'zustand';

type ViewMode = 'map' | 'list';

interface MapFilters {
  sportKey: string | null;
  dateRange: 'today' | 'week' | 'all';
}

interface MapStore {
  viewMode: ViewMode;
  filters: MapFilters;
  setViewMode: (mode: ViewMode) => void;
  toggleViewMode: () => void;
  setSportFilter: (sportKey: string | null) => void;
  setDateFilter: (range: MapFilters['dateRange']) => void;
  resetFilters: () => void;
}

const DEFAULT_FILTERS: MapFilters = {
  sportKey: null,
  dateRange: 'all',
};

export const useMapStore = create<MapStore>((set) => ({
  viewMode: 'map',
  filters: DEFAULT_FILTERS,
  setViewMode: (mode) => set({ viewMode: mode }),
  toggleViewMode: () =>
    set((state) => ({ viewMode: state.viewMode === 'map' ? 'list' : 'map' })),
  setSportFilter: (sportKey) =>
    set((state) => ({ filters: { ...state.filters, sportKey } })),
  setDateFilter: (dateRange) =>
    set((state) => ({ filters: { ...state.filters, dateRange } })),
  resetFilters: () => set({ filters: DEFAULT_FILTERS }),
}));
