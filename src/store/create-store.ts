import { create } from 'zustand';

interface CreateFormState {
  sport_id: string;
  title: string;
  description: string;
  level: string;
  max_participants: number;
  location_start: { lng: number; lat: number } | null;
  location_meeting: { lng: number; lat: number } | null;
  starts_at: Date | null;
  duration_hours: number;
  duration_minutes: number;
  visibility: 'public' | 'approval' | 'private_link' | 'private_link_approval';
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
  max_participants: 4,
  location_start: null,
  location_meeting: null,
  starts_at: null,
  duration_hours: 2,
  duration_minutes: 0,
  visibility: 'public',
};

export const useCreateStore = create<CreateStore>((set) => ({
  form: DEFAULT_FORM,
  updateForm: (updates) =>
    set((state) => ({ form: { ...state.form, ...updates } })),
  resetForm: () => set({ form: DEFAULT_FORM }),
}));
