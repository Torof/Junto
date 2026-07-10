import * as Location from 'expo-location';
import { supabase } from '@/services/supabase';
import { trace, captureInfo, captureWarning } from './sentry';
import {
  PRESENCE_LOCATION_TASK,
  setLocationTaskCandidates,
  clearLocationTaskCandidates,
  setOnAllValidated,
  type PresenceCandidate,
} from './presence-location-task';

// Window mirrors the foreground watcher and the server-side gate on
// confirm_presence_via_geo: only fire when the activity is in
// T-15min..T+15min of starts_at.
const WINDOW_BEFORE_MS = 15 * 60_000;
const WINDOW_AFTER_MS = 15 * 60_000;

interface ActiveActivity {
  activity_id: string;
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
    if (lng == null || lat == null) continue;
    result.push({ activity_id: a.activity_id, lng, lat, starts_at: a.starts_at });
  }
  return result;
}

let serviceRunning = false;
let stopTimer: ReturnType<typeof setTimeout> | null = null;

// Best-effort fast path only: RN timers freeze while the app is
// backgrounded, so the AUTHORITATIVE deadline is the window check at the
// top of the location task callback (the only code the OS guarantees keeps
// running). This timer just stops the service a bit sooner when the app
// happens to be foregrounded.
function scheduleStopTimer(candidates: PresenceCandidate[]): void {
  const latestEnd = Math.max(
    ...candidates.map((c) => new Date(c.starts_at).getTime() + WINDOW_AFTER_MS),
  );
  const msUntilStop = Math.max(0, latestEnd - Date.now());
  if (stopTimer) clearTimeout(stopTimer);
  stopTimer = setTimeout(() => {
    void stopPresenceForegroundService('window passed');
  }, msUntilStop);
}

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
  // The OS is the source of truth, not the module flag: after a process
  // kill the Android foreground service survives with a fresh JS runtime
  // where serviceRunning is back to false. Trusting the flag alone either
  // no-ops against a dead service or leaks an orphaned one.
  const osRunning = await Location.hasStartedLocationUpdatesAsync(PRESENCE_LOCATION_TASK).catch(
    () => false,
  );

  if (serviceRunning && osRunning) {
    // Refresh the candidate set instead of a pure no-op — a second
    // activity may have entered its window while the service was already
    // running for the first (the task's validated set is preserved so
    // settled activities aren't re-fired), and the stop deadline must
    // stretch to cover the newcomer.
    const fresh = await fetchInWindowCandidates();
    if (fresh.length > 0) {
      setLocationTaskCandidates(fresh);
      scheduleStopTimer(fresh);
    }
    trace('presence.fgservice', 'already running, candidates refreshed', {
      candidate_count: fresh.length,
    });
    return true;
  }

  const bg = await Location.getBackgroundPermissionsAsync();
  if (bg.status !== 'granted') {
    trace('presence.fgservice', 'no background permission, skipping');
    if (osRunning) await stopOsService('no background permission (orphan)');
    return false;
  }

  const candidates = await fetchInWindowCandidates();
  if (candidates.length === 0) {
    trace('presence.fgservice', 'no in-window candidates, skipping');
    // An OS-level service with zero in-window candidates is an orphan
    // (killed process, stale window) — reap it instead of leaving a
    // persistent notif + GPS polling until reboot.
    if (osRunning) await stopOsService('no in-window candidates (orphan)');
    return false;
  }

  setLocationTaskCandidates(candidates);
  setOnAllValidated((reason) => {
    void stopPresenceForegroundService(reason);
  });

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
        notificationColor: '#2FA46A',
      },
    });
    serviceRunning = true;
    captureInfo('presence.fgservice', 'started', { candidate_count: candidates.length });
    scheduleStopTimer(candidates);
    return true;
  } catch (err) {
    captureWarning('presence.fgservice', 'failed to start', {
      reason: err instanceof Error ? err.message : String(err),
    });
    clearLocationTaskCandidates();
    return false;
  }
}

async function stopOsService(reason: string): Promise<void> {
  try {
    await Location.stopLocationUpdatesAsync(PRESENCE_LOCATION_TASK);
  } catch (err) {
    trace('presence.fgservice', 'orphan stop threw', {
      message: err instanceof Error ? err.message : String(err),
    });
  }
  clearLocationTaskCandidates();
  trace('presence.fgservice', 'orphan service stopped', { reason });
}

export async function stopPresenceForegroundService(reason: string): Promise<void> {
  // No early-return on !serviceRunning: the flag is per-JS-runtime while
  // the OS service is per-process-lifetime — always ask the OS.
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
  setOnAllValidated(null);
  clearLocationTaskCandidates();
  serviceRunning = false;
  trace('presence.fgservice', 'stopped', { reason });
}
