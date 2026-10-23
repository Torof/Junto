import { create } from 'zustand';

// The full-card pager swipes through the people of the list it was opened
// from, in that list's order (carousel, « Tout voir », filtered or not).
// The opening screen writes the ordered user ids here before navigating.
interface PartnersPagerStore {
  userIds: string[];
  setUserIds: (ids: string[]) => void;
}

export const usePartnersPagerStore = create<PartnersPagerStore>((set) => ({
  userIds: [],
  setUserIds: (userIds) => set({ userIds }),
}));
