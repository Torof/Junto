import { create } from 'zustand';

export type TutorialStep =
  | 'idle'
  | 'click_activity'
  | 'open_popup'
  | 'click_alert'
  | 'set_radius'
  | 'validate_alert'
  | 'create_activity_hint'
  | 'done';

interface TutorialState {
  step: TutorialStep;
  demoActivityId: string | null;
  setStep: (step: TutorialStep) => void;
  setDemoActivityId: (id: string | null) => void;
}

export const useTutorialStore = create<TutorialState>((set) => ({
  step: 'idle',
  demoActivityId: null,
  setStep: (step) => set({ step }),
  setDemoActivityId: (id) => set({ demoActivityId: id }),
}));
