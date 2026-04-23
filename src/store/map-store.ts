import { create } from 'zustand';

type ViewMode = 'map' | 'list';
type DateFilterMode = 'all' | 'today' | 'week' | 'date' | 'range';

export type LevelTier = 'Débutant' | 'Intermédiaire' | 'Avancé' | 'Expert';
export type VisibilityFilter = 'public' | 'approval';

interface MapFilters {
  sportKeys: string[];
  dateMode: DateFilterMode;
  specificDate: string | null;   // ISO date string for 'date' mode
  rangeFrom: string | null;      // ISO date string for 'range' mode
  rangeTo: string | null;        // ISO date string for 'range' mode
  levelTiers: LevelTier[];       // empty = no filter
  visibilities: VisibilityFilter[]; // empty = no filter
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
  toggleLevelTier: (tier: LevelTier) => void;
  toggleVisibility: (v: VisibilityFilter) => void;
  resetFilters: () => void;
}

const DEFAULT_FILTERS: MapFilters = {
  sportKeys: [],
  dateMode: 'all',
  specificDate: null,
  rangeFrom: null,
  rangeTo: null,
  levelTiers: [],
  visibilities: [],
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
  toggleLevelTier: (tier) =>
    set((state) => ({
      filters: {
        ...state.filters,
        levelTiers: state.filters.levelTiers.includes(tier)
          ? state.filters.levelTiers.filter((t) => t !== tier)
          : [...state.filters.levelTiers, tier],
      },
    })),
  toggleVisibility: (v) =>
    set((state) => ({
      filters: {
        ...state.filters,
        visibilities: state.filters.visibilities.includes(v)
          ? state.filters.visibilities.filter((x) => x !== v)
          : [...state.filters.visibilities, v],
      },
    })),
  resetFilters: () => set({ filters: DEFAULT_FILTERS }),
}));
