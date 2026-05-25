import { supabase } from './supabase';
import { readDeviceId } from '@/utils/device-id';

export const pushTokenService = {
  // Revoke the push token registered for the current device. Best-
  // effort: silently no-ops if no device_id is persisted yet, if the
  // RPC errors (e.g. auth gone), or if there was no token to revoke.
  // Called from authService.signOut (before clearing the session) and
  // from the push hook when the OS permission becomes "denied".
  revokeForCurrentDevice: async (): Promise<void> => {
    const deviceId = await readDeviceId();
    if (!deviceId) return;
    try {
      await supabase.rpc('revoke_push_token_for_device', { p_device_id: deviceId });
    } catch {
      // Swallow — this is cleanup, not user-facing. Stale tokens just
      // get pruned later by other paths (suspension trigger, manual
      // ops) if this call fails.
    }
  },
};
