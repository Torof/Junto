import { create } from 'zustand';

// The tour (IntroCarousel) lives in carte.tsx. Since 2026-10-24 it no longer
// opens by itself: carte decides whether to OFFER it (`offerVisible` — first
// week of the account, until the tour is opened or closed) and the menu shows
// its « Découvrir l'app » entry while the offer stands. « Revoir l'intro » in
// Settings and that menu entry ask carte to open it (`requestReplay`).
interface IntroState {
  replayRequested: boolean;
  requestReplay: () => void;
  clearReplay: () => void;
  offerVisible: boolean;
  setOfferVisible: (visible: boolean) => void;
}

export const useIntroStore = create<IntroState>((set) => ({
  replayRequested: false,
  requestReplay: () => set({ replayRequested: true }),
  clearReplay: () => set({ replayRequested: false }),
  offerVisible: false,
  setOfferVisible: (offerVisible) => set({ offerVisible }),
}));
