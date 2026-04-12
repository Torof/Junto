import { create } from 'zustand';

type ViewMode = 'map' | 'list';

interface MapFilters {
  sportKeys: string[];
  dateRange: 'today' | 'week' | 'all';
}

interface MapStore {
  viewMode: ViewMode;
  filters: MapFilters;
  setViewMode: (mode: ViewMode) => void;
  toggleViewMode: () => void;
  toggleSportFilter: (sportKey: string) => void;
  setDateFilter: (range: MapFilters['dateRange']) => void;
  resetFilters: () => void;
}

const DEFAULT_FILTERS: MapFilters = {
  sportKeys: [],
  dateRange: 'all',
};

export const useMapStore = create<MapStore>((set) => ({
  viewMode: 'map',
  filters: DEFAULT_FILTERS,
  setViewMode: (mode) => set({ viewMode: mode }),
  toggleViewMode: () =>
    set((state) => ({ viewMode: state.viewMode === 'map' ? 'list' : 'map' })),
  toggleSportFilter: (sportKey) =>
    set((state) => ({
      filters: {
        ...state.filters,
        sportKeys: state.filters.sportKeys.includes(sportKey)
          ? state.filters.sportKeys.filter((k) => k !== sportKey)
          : [...state.filters.sportKeys, sportKey],
      },
    })),
  setDateFilter: (dateRange) =>
    set((state) => ({ filters: { ...state.filters, dateRange } })),
  resetFilters: () => set({ filters: DEFAULT_FILTERS }),
}));
