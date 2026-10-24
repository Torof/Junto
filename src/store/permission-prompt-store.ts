import { create } from 'zustand';

// The in-app explanation shown BEFORE any OS permission dialog (Scott
// 2026-10-24: ask at the moment it serves, always explain first). One card at
// a time; lib/permissions.ts opens it and waits for the answer.

export type PermissionKind = 'location' | 'notifications' | 'camera';
export type PermissionReason =
  | 'locate'      // the map's « me localiser » button
  | 'aroundMe'    // « Autour de moi » in the discussions search
  | 'checkin'     // confirming presence on site
  | 'join'        // just joined an outing
  | 'joinRequest' // just asked to join an outing
  | 'create'      // just published an outing
  | 'contact'     // just sent a contact request
  | 'scan';       // scanning a QR code

export interface PermissionCard {
  kind: PermissionKind;
  reason: PermissionReason;
  // The OS will not show its dialog any more: the card offers the settings.
  blocked: boolean;
}

interface PermissionPromptStore {
  card: PermissionCard | null;
  resolver: ((allow: boolean) => void) | null;
  // Foreground location granted — every useInitialLocation starts locating
  // the moment this flips, without asking anything itself.
  locationGranted: boolean;
  open: (card: PermissionCard) => Promise<boolean>;
  answer: (allow: boolean) => void;
  setLocationGranted: (granted: boolean) => void;
}

export const usePermissionPromptStore = create<PermissionPromptStore>((set, get) => ({
  card: null,
  resolver: null,
  locationGranted: false,
  open: (card) => {
    // A card already up answers « later » before the new one replaces it.
    get().resolver?.(false);
    return new Promise<boolean>((resolve) => set({ card, resolver: resolve }));
  },
  answer: (allow) => {
    const { resolver } = get();
    set({ card: null, resolver: null });
    resolver?.(allow);
  },
  setLocationGranted: (locationGranted) => set({ locationGranted }),
}));
