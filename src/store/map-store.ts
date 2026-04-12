import { create } from 'zustand';

type ViewMode = 'map' | 'list';
type DateFilterMode = 'all' | 'today' | 'week' | 'date' | 'range';

interface MapFilters {
  sportKeys: string[];
  dateMode: DateFilterMode;
  specificDate: string | null;   // ISO date string for 'date' mode
  rangeFrom: string | null;      // ISO date string for 'range' mode
  rangeTo: string | null;        // ISO date string for 'range' mode
}

interface MapStore {
  viewMode: ViewMode;
  filters: MapFilters;
  setViewMode: (mode: ViewMode) => void;
  toggleViewMode: () => void;
  toggleSportFilter: (sportKey: string) => void;
  setDateMode: (mode: DateFilterMode) => void;
  setSpecificDate: (date: string) => void;
  setDateRange: (from: string, to: string) => void;
  resetFilters: () => void;
}

const DEFAULT_FILTERS: MapFilters = {
  sportKeys: [],
  dateMode: 'all',
  specificDate: null,
  rangeFrom: null,
  rangeTo: null,
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
  setDateMode: (dateMode) =>
    set((state) => ({ filters: { ...state.filters, dateMode } })),
  setSpecificDate: (date) =>
    set((state) => ({ filters: { ...state.filters, dateMode: 'date', specificDate: date } })),
  setDateRange: (from, to) =>
    set((state) => ({ filters: { ...state.filters, dateMode: 'range', rangeFrom: from, rangeTo: to } })),
  resetFilters: () => set({ filters: DEFAULT_FILTERS }),
}));
