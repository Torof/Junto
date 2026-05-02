import * as Location from 'expo-location';
import { supabase } from '@/services/supabase';
import { trace, captureInfo, captureWarning } from './sentry';
import {
  PRESENCE_LOCATION_TASK,
  setLocationTaskCandidates,
  getLocationTaskCandidates,
  clearLocationTaskCandidates,
  clearValidatedFor,
  type PresenceCandidate,
} from './presence-location-task';

// Window mirrors the foreground watcher and the server-side gate on
// confirm_presence_via_geo: only fire when the activity is in
// T-15min..T+15min of starts_at.
export const WINDOW_BEFORE_MS = 15 * 60_000;
export const WINDOW_AFTER_MS = 15 * 60_000;

interface ActiveActivity {
  activity_id: string;
  start_lng: number | null;
  start_lat: number | null;
  meeting_lng: number | null;
  meeting_lat: number | null;
  end_lng: number | null;
  end_lat: number | null;
  starts_at: string;
}

async function fetchInWindowCandidates(): Promise<PresenceCandidate[]> {
  const { data } = (await supabase.rpc('get_my_active_presence_activities' as 'accept_tos')) as unknown as {
    data: ActiveActivity[] | null;
  };
  const rows = data ?? [];
  const now = Date.now();
  const result: PresenceCandidate[] = [];
  for (const a of rows) {
    const t = new Date(a.starts_at).getTime();
    if (t - WINDOW_BEFORE_MS > now || now > t + WINDOW_AFTER_MS) continue;
    let lng = a.meeting_lng;
    let lat = a.meeting_lat;
    if (lng == null || lat == null) {
      lng = a.start_lng;
      lat = a.start_lat;
    }
    if (lng == null || lat == null) continue;
    result.push({ activity_id: a.activity_id, lng, lat, starts_at: a.starts_at });
  }
  return result;
}

// stopTimer is module state we own; running-state is read from the OS so
// it reflects reality even when the location task self-stopped via
// Location.stopLocationUpdatesAsync without going through this module.
let stopTimer: ReturnType<typeof setTimeout> | null = null;

/**
 * Start the foreground location service if there's at least one in-window
 * candidate activity. The service runs `Location.startLocationUpdatesAsync`
 * with a `foregroundService` config — Android shows a persistent
 * notification while it runs, which is what keeps the OS from killing the
 * process. iOS does not require this notification but the API is the same.
 *
 * Idempotent: calling it twice is safe; the second call no-ops if the
 * service is already running.
 *
 * Returns whether the service is actually running after this call.
 */
export async function startPresenceForegroundService(): Promise<boolean> {
  // Source of truth is the OS, not a module-level flag. The location
  // task can call Location.stopLocationUpdatesAsync directly (when it
  // detects all candidates validated), in which case a module flag
  // would go stale and we'd refuse to restart on a future window.
  const alreadyRunning = await Location.hasStartedLocationUpdatesAsync(
    PRESENCE_LOCATION_TASK,
  ).catch(() => false);
  if (alreadyRunning) {
    captureInfo('presence.fgservice', 'already running, no-op');
    return true;
  }

  const bg = await Location.getBackgroundPermissionsAsync();
  if (bg.status !== 'granted') {
    captureInfo('presence.fgservice', 'no background permission, skipping');
    return false;
  }

  const candidates = await fetchInWindowCandidates();
  if (candidates.length === 0) {
    captureInfo('presence.fgservice', 'no in-window candidates, skipping');
    return false;
  }

  // Clear any stale validated flags from a prior session for these
  // activities — a re-joined activity or a re-tested one needs to be
  // treated as fresh.
  await clearValidatedFor(candidates.map((c) => c.activity_id));
  setLocationTaskCandidates(candidates);

  try {
    await Location.startLocationUpdatesAsync(PRESENCE_LOCATION_TASK, {
      accuracy: Location.Accuracy.High,
      timeInterval: 10_000,
      distanceInterval: 20,
      pausesUpdatesAutomatically: false,
      showsBackgroundLocationIndicator: true,
      foregroundService: {
        notificationTitle: 'Junto valide ta présence',
        notificationBody:
          'Détection automatique active pendant la fenêtre de présence',
        notificationColor: '#F4642A',
      },
    });
    captureInfo('presence.fgservice', 'started', { candidate_count: candidates.length });

    // Schedule auto-stop at T+15min of the latest candidate. After that,
    // the server-side window is closed and there's nothing to do —
    // burning GPS for a user who didn't show up wastes their battery.
    const latestEnd = Math.max(
      ...candidates.map((c) => new Date(c.starts_at).getTime() + WINDOW_AFTER_MS),
    );
    const msUntilStop = Math.max(0, latestEnd - Date.now());
    if (stopTimer) clearTimeout(stopTimer);
    stopTimer = setTimeout(() => {
      void stopPresenceForegroundService('window passed');
    }, msUntilStop);

    return true;
  } catch (err) {
    captureWarning('presence.fgservice', 'failed to start', {
      reason: err instanceof Error ? err.message : String(err),
    });
    clearLocationTaskCandidates();
    return false;
  }
}

export async function stopPresenceForegroundService(reason: string): Promise<void> {
  if (stopTimer) {
    clearTimeout(stopTimer);
    stopTimer = null;
  }
  try {
    const isRunning = await Location.hasStartedLocationUpdatesAsync(PRESENCE_LOCATION_TASK).catch(
      () => false,
    );
    if (isRunning) {
      await Location.stopLocationUpdatesAsync(PRESENCE_LOCATION_TASK);
    }
  } catch (err) {
    trace('presence.fgservice', 'stop threw', {
      message: err instanceof Error ? err.message : String(err),
    });
  }
  // Clear AsyncStorage for the candidates we were tracking — next session
  // (or a different activity later) starts fresh.
  const ids = getLocationTaskCandidates().map((c) => c.activity_id);
  await clearValidatedFor(ids);
  clearLocationTaskCandidates();
  trace('presence.fgservice', 'stopped', { reason });
}
