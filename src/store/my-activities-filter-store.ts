import { create } from 'zustand';
import type { LevelTier, VisibilityFilter, SortBy } from './map-store';

// Separate filter state for the my-activities screen so its filter
// modal doesn't share state with the map's FilterSheet (Scott 2026-05-12:
// 'let's not apply the filters for my activities to the ones on the map
// and vice versa').
//
// Same shape and actions as useMapStore — different state. Both stores
// are consumed by the same FilterSheet / SportPickerSheet / LevelPickerSheet
// components via the `useStore` prop those components now accept.

type DateFilterMode = 'all' | 'today' | 'week' | 'date' | 'range';

interface MapFilters {
  sportKeys: string[];
  dateMode: DateFilterMode;
  specificDate: string | null;
  rangeFrom: string | null;
  rangeTo: string | null;
  levelTiers: LevelTier[];
  visibilities: VisibilityFilter[];
  radiusKm: number | null;
  sortBy: SortBy;
}

interface FilterStore {
  filters: MapFilters;
  toggleSportFilter: (sportKey: string) => void;
  setDateMode: (mode: DateFilterMode) => void;
  setSpecificDate: (date: string) => void;
  setDateRange: (from: string, to: string) => void;
  toggleLevelTier: (tier: LevelTier) => void;
  toggleVisibility: (v: VisibilityFilter) => void;
  setRadiusKm: (km: number | null) => void;
  setSortBy: (sort: SortBy) => void;
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
  radiusKm: null,
  sortBy: 'date',
};

export const useMyActivitiesFilterStore = create<FilterStore>((set) => ({
  filters: DEFAULT_FILTERS,
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
  setRadiusKm: (km) =>
    set((state) => ({ filters: { ...state.filters, radiusKm: km } })),
  setSortBy: (sortBy) =>
    set((state) => ({ filters: { ...state.filters, sortBy } })),
  resetFilters: () => set({ filters: DEFAULT_FILTERS }),
}));
