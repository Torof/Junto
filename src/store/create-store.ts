import { create } from 'zustand';
import type { GeoJsonLineString } from '@/services/activity-service';

interface CreateFormState {
  sport_id: string;
  title: string;
  description: string;
  level: string;
  distance_km: number | null;
  elevation_gain_m: number | null;
  max_participants: number;
  location_start: { lng: number; lat: number } | null;
  location_meeting: { lng: number; lat: number } | null;
  location_end: { lng: number; lat: number } | null;
  location_objective: { lng: number; lat: number } | null;
  objective_name: string;
  start_name: string;
  trace_geojson: GeoJsonLineString | null;
  starts_at: Date | null;
  duration_hours: number;
  duration_minutes: number;
  visibility: 'public' | 'approval' | 'private_link' | 'private_link_approval';
  requires_presence: boolean;
}

interface CreateStore {
  form: CreateFormState;
  updateForm: (updates: Partial<CreateFormState>) => void;
  resetForm: () => void;
}

const DEFAULT_FORM: CreateFormState = {
  sport_id: '',
  title: '',
  description: '',
  level: '',
  distance_km: null,
  elevation_gain_m: null,
  max_participants: 4,
  location_start: null,
  location_meeting: null,
  location_end: null,
  location_objective: null,
  objective_name: '',
  start_name: '',
  trace_geojson: null,
  starts_at: null,
  duration_hours: 2,
  duration_minutes: 0,
  visibility: 'public',
  requires_presence: true,
};

export const useCreateStore = create<CreateStore>((set) => ({
  form: DEFAULT_FORM,
  updateForm: (updates) =>
    set((state) => ({ form: { ...state.form, ...updates } })),
  resetForm: () => set({ form: DEFAULT_FORM }),
}));
