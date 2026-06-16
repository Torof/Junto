import { create } from 'zustand';

// Lets the settings drawer ask the map screen to replay the first-run
// IntroCarousel ("Revoir l'intro"). The carousel itself lives in carte.tsx;
// the drawer just flips this flag and carte reacts.
interface IntroState {
  replayRequested: boolean;
  requestReplay: () => void;
  clearReplay: () => void;
}

export const useIntroStore = create<IntroState>((set) => ({
  replayRequested: false,
  requestReplay: () => set({ replayRequested: true }),
  clearReplay: () => set({ replayRequested: false }),
}));
