import { create } from 'zustand';
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Font from 'expo-font';
import { DEFAULT_FONT_FAMILY, fontFileMap, isFontFamilyId, type FontFamilyId } from '@/constants/font-families';

// The app's font family (Settings → Personnalisation). `family` is the family
// ACTIVELY rendered and only ever names a loaded one: a Text rendered with a
// not-yet-registered family name would keep the fallback face for good (no
// re-render when the file lands), so the store switches only after loadAsync
// resolves. A family that fails to load leaves the app on the system font.
// Local display preference, persisted on the device only.

const STORAGE_KEY = 'junto_font_family';

interface FontStore {
  family: FontFamilyId;
  ready: boolean;
  init: () => Promise<void>;
  setFamily: (id: FontFamilyId) => Promise<boolean>;
}

async function loadFamily(id: FontFamilyId): Promise<void> {
  if (id === 'system') return;
  await Font.loadAsync(fontFileMap(id));
}

export const useFontStore = create<FontStore>((set) => ({
  family: 'system',
  ready: false,
  init: async () => {
    let wanted: FontFamilyId = DEFAULT_FONT_FAMILY;
    try {
      const stored = await AsyncStorage.getItem(STORAGE_KEY);
      if (isFontFamilyId(stored)) wanted = stored;
    } catch {
      // keep the default
    }
    try {
      await loadFamily(wanted);
      set({ family: wanted, ready: true });
    } catch {
      set({ family: 'system', ready: true });
    }
  },
  setFamily: async (id) => {
    try {
      await loadFamily(id);
    } catch {
      return false;
    }
    set({ family: id });
    AsyncStorage.setItem(STORAGE_KEY, id).catch(() => {});
    return true;
  },
}));
