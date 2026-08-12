import { create } from 'zustand';
import type { GeoJsonLineString } from '@/services/activity-service';

interface CreateFormState {
  sport_id: string;
  title: string;
  description: string;
  level: string;
  level_max: string | null;
  distance_km: number | null;
  elevation_gain_m: number | null;
  max_participants: number | null;
  location_meeting: { lng: number; lat: number } | null;
  location_end: { lng: number; lat: number } | null;
  location_objective: { lng: number; lat: number } | null;
  objective_name: string;
  meeting_name: string;
  trace_geojson: GeoJsonLineString | null;
  starts_at: Date | null;
  duration_hours: number;
  duration_minutes: number;
  visibility: 'public' | 'approval' | 'private_link' | 'private_link_approval';
  requires_presence: boolean;
  // Partners to invite-to-join on publish (Brique 4e-2). Sent best-effort after
  // the activity is created (creator-only, pre-approved). User ids.
  invitees: string[];
}

interface CreateStore {
  form: CreateFormState;
  updateForm: (updates: Partial<CreateFormState>) => void;
  resetForm: () => void;
  // When an activity is created from a channel ("Proposer une sortie"), post its
  // card into that conversation on publish, then land there. Cleared on consume.
  shareToConversationId: string | null;
  setShareTo: (conversationId: string | null) => void;
}

const DEFAULT_FORM: CreateFormState = {
  sport_id: '',
  title: '',
  description: '',
  level: '',
  level_max: null,
  distance_km: null,
  elevation_gain_m: null,
  max_participants: 4,
  location_meeting: null,
  location_end: null,
  location_objective: null,
  objective_name: '',
  meeting_name: '',
  trace_geojson: null,
  starts_at: null,
  duration_hours: 2,
  duration_minutes: 0,
  visibility: 'public',
  requires_presence: true,
  invitees: [],
};

export const useCreateStore = create<CreateStore>((set) => ({
  form: DEFAULT_FORM,
  updateForm: (updates) =>
    set((state) => ({ form: { ...state.form, ...updates } })),
  // resetForm also clears the channel post-back target, so an abandoned
  // "Proposer une sortie" never leaks into a later normal creation.
  resetForm: () => set({ form: DEFAULT_FORM, shareToConversationId: null }),
  shareToConversationId: null,
  setShareTo: (conversationId) => set({ shareToConversationId: conversationId }),
}));
