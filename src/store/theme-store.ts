import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import AsyncStorage from '@react-native-async-storage/async-storage';

export type ThemePreference = 'light' | 'dark' | 'system';

interface ThemeStore {
  preference: ThemePreference;
  setPreference: (pref: ThemePreference) => void;
  // Accent override (hex). null = follow the theme's default `cta`. When set,
  // the ThemeProvider injects it into the `cta` token → the whole app recolors.
  // Purely a display preference, persisted locally (no server).
  accent: string | null;
  setAccent: (accent: string | null) => void;
}

export const useThemeStore = create<ThemeStore>()(
  persist(
    (set) => ({
      // Light is Junto's primary theme (2026-06-11) — outdoor sunlight
      // readability. Dark is an explicit opt-in via settings.
      preference: 'light',
      setPreference: (preference) => set({ preference }),
      accent: null,
      setAccent: (accent) => set({ accent }),
    }),
    {
      name: 'junto-theme',
      storage: createJSONStorage(() => AsyncStorage),
    },
  ),
);
