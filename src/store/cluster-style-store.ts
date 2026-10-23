import { create } from 'zustand';
import AsyncStorage from '@react-native-async-storage/async-storage';

// Map cluster look (Scott 2026-10-21): coloured universe ring on/off + its
// thickness. Built to show both looks to testers; kept as a user preference.
// Off by default (Scott 2026-10-23): the plain cluster first, colour on request.
export const CLUSTER_RING_WIDTHS = [3, 5, 7] as const;
export type ClusterRingWidth = (typeof CLUSTER_RING_WIDTHS)[number];

const STORAGE_KEY = 'junto_cluster_style';

interface ClusterStyleStore {
  ringOn: boolean;
  ringWidth: ClusterRingWidth;
  load: () => Promise<void>;
  setRingOn: (on: boolean) => void;
  setRingWidth: (w: ClusterRingWidth) => void;
}

function persist(s: { ringOn: boolean; ringWidth: ClusterRingWidth }) {
  AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(s)).catch(() => {});
}

export const useClusterStyleStore = create<ClusterStyleStore>((set, get) => ({
  ringOn: false,
  ringWidth: 5,
  load: async () => {
    try {
      const raw = await AsyncStorage.getItem(STORAGE_KEY);
      if (!raw) return;
      const v = JSON.parse(raw) as { ringOn?: unknown; ringWidth?: unknown };
      set({
        ringOn: typeof v.ringOn === 'boolean' ? v.ringOn : false,
        ringWidth: (CLUSTER_RING_WIDTHS as readonly unknown[]).includes(v.ringWidth) ? (v.ringWidth as ClusterRingWidth) : 5,
      });
    } catch {
      // keep defaults
    }
  },
  setRingOn: (ringOn) => {
    set({ ringOn });
    persist({ ringOn, ringWidth: get().ringWidth });
  },
  setRingWidth: (ringWidth) => {
    set({ ringWidth });
    persist({ ringOn: get().ringOn, ringWidth });
  },
}));
