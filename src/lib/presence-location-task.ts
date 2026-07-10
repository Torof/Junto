import * as TaskManager from 'expo-task-manager';
import * as Location from 'expo-location';
import * as Notifications from 'expo-notifications';
import { supabase } from '@/services/supabase';
import { trace, captureInfo } from './sentry';
import { distanceMeters } from '@/utils/geo';
import { isTerminalPresenceRejection } from './presence-offline-cache';

// Task name registered at module-load time. Imported from app/_layout so
// the OS can find this task definition when it spawns the headless JS
// runtime to deliver location updates.
export const PRESENCE_LOCATION_TASK = 'junto.presence-location';

// Mirrors the geofence task / foreground watcher.
const RADIUS_M = 300;
const ACCURACY_THRESHOLD_M = 100;
const WINDOW_AFTER_MS = 15 * 60_000;

// Candidates the service is currently watching. Cleared when the service
// stops. Set by presence-foreground-service before it calls
// Location.startLocationUpdatesAsync.
export interface PresenceCandidate {
  activity_id: string;
  lng: number;
  lat: number;
  // ISO timestamp of activity start. Used to stop the service after
  // T+15min if the user never showed up — no point burning battery
  // forever.
  starts_at: string;
}

// Module-level state. Survives across location callbacks within a single
// JS runtime session. If the OS resets the JS runtime mid-service (rare
// for active foreground services, but possible), we'll re-seed from the
// service module on next start.
let candidates: PresenceCandidate[] = [];
const validated = new Set<string>();
let onAllValidated: (() => void) | null = null;

export function setLocationTaskCandidates(next: PresenceCandidate[]): void {
  candidates = next.slice();
  validated.clear();
}

export function clearLocationTaskCandidates(): void {
  candidates = [];
  validated.clear();
}

export function hasOpenCandidates(): boolean {
  return candidates.some((c) => !validated.has(c.activity_id));
}

// Registered by the foreground service module when it starts the service.
// The location task calls this when every candidate is validated so the
// service can stop itself instead of polling forever.
export function setOnAllValidated(cb: (() => void) | null): void {
  onAllValidated = cb;
}

interface LocationTaskPayload {
  locations?: Location.LocationObject[];
}

// Stop the service from inside the task. The normal in-app path goes
// through the registered callback (the service module clears its own
// state); in a FRESH headless context (process killed while the Android
// foreground service survived) that callback is null and the service
// module's `serviceRunning` flag is a lie — ask the OS directly, or the
// orphaned service outlives everything until reboot (persistent notif +
// high-accuracy GPS forever).
async function stopSelf(reason: string): Promise<void> {
  if (onAllValidated) {
    onAllValidated();
    return;
  }
  try {
    const running = await Location.hasStartedLocationUpdatesAsync(PRESENCE_LOCATION_TASK);
    if (running) await Location.stopLocationUpdatesAsync(PRESENCE_LOCATION_TASK);
  } catch (err) {
    trace('presence.location', 'stopSelf threw', {
      message: err instanceof Error ? err.message : String(err),
    });
  }
  clearLocationTaskCandidates();
  trace('presence.location', 'stopped self', { reason });
}

TaskManager.defineTask(PRESENCE_LOCATION_TASK, async ({ data, error }) => {
  if (error) {
    trace('presence.location', 'task fired with error', { reason: String(error) });
    return;
  }

  // Orphan guard: a fresh headless context has no candidates — nothing
  // useful can ever happen in this service again. Kill it.
  if (candidates.length === 0) {
    await stopSelf('no candidates (fresh JS context after process kill)');
    return;
  }

  // The deadline lives HERE, not in a setTimeout: RN timers freeze while
  // the app is backgrounded, and this callback is the only code the OS
  // guarantees keeps running. Without this, a no-show user + backgrounded
  // app = high-accuracy GPS all night (Android battery-shaming report).
  const nowMs = Date.now();
  const allSettled = candidates.every(
    (c) => validated.has(c.activity_id) || nowMs > new Date(c.starts_at).getTime() + WINDOW_AFTER_MS,
  );
  if (allSettled) {
    await stopSelf('window passed or validated for all candidates');
    return;
  }

  const { locations } = (data ?? {}) as LocationTaskPayload;
  if (!locations || locations.length === 0) return;

  // Pick the freshest sample with usable accuracy. The service emits
  // batches when it catches up after a Doze interval — old samples in the
  // batch are stale, only the latest matters for an in-zone decision.
  const fix = locations[locations.length - 1];
  if (!fix) return;
  if (fix.coords.accuracy != null && fix.coords.accuracy > ACCURACY_THRESHOLD_M) {
    trace('presence.location', 'sample too coarse, skipping', {
      accuracy_m: Math.round(fix.coords.accuracy),
    });
    return;
  }

  const { data: sessionData } = await supabase.auth.getSession();
  if (!sessionData?.session) {
    trace('presence.location', 'no session, skipping');
    return;
  }

  for (const candidate of candidates) {
    if (validated.has(candidate.activity_id)) continue;

    const d = distanceMeters(
      fix.coords.latitude,
      fix.coords.longitude,
      candidate.lat,
      candidate.lng,
    );
    if (d > RADIUS_M) continue;

    captureInfo('presence.location', 'in zone, calling RPC', {
      distance_m: Math.round(d),
      accuracy_m: fix.coords.accuracy != null ? Math.round(fix.coords.accuracy) : null,
    });

    try {
      const { error: rpcError } = await supabase.rpc('confirm_presence_via_geo' as 'join_activity', {
        p_activity_id: candidate.activity_id,
        p_lng: fix.coords.longitude,
        p_lat: fix.coords.latitude,
        p_skip_push: true,
      } as unknown as { p_activity_id: string });

      if (!rpcError) {
        validated.add(candidate.activity_id);
        // Local notif transition mirrors the geofence task path (cancel the
        // pending deferred détectée too — dismiss only clears the tray).
        const slotId = `presence-${candidate.activity_id}`;
        await Notifications.cancelScheduledNotificationAsync(slotId).catch(() => {});
        await Notifications.dismissNotificationAsync(slotId).catch(() => {});
        Notifications.scheduleNotificationAsync({
          identifier: `${slotId}-confirmed`,
          content: {
            title: 'Présence confirmée',
            body: 'Ta présence à cette activité est confirmée.',
            data: { activity_id: candidate.activity_id, type: 'presence_confirmed' },
            sound: true,
          },
          trigger: null,
        }).catch(() => {});
        continue;
      }

      // Server function is idempotent (mig 00163) so 'already confirmed'
      // returns success. Coded junto.presence_* gates and auth-chain
      // rejections are terminal — mark validated locally so we stop
      // re-firing the RPC every 10s sample while the user lingers nearby.
      if (isTerminalPresenceRejection(rpcError.message)) {
        validated.add(candidate.activity_id);
        trace('presence.location', 'RPC rejected (terminal), skipping further checks', {
          reason: rpcError.message,
        });
      } else {
        trace('presence.location', 'RPC failed (transient), will retry on next sample', {
          reason: rpcError.message,
        });
      }
    } catch (err) {
      trace('presence.location', 'RPC threw, will retry on next sample', {
        message: err instanceof Error ? err.message : String(err),
      });
    }
  }

  // All candidates settled — fire the stop callback if registered. The
  // service module will tear down the location updates and clear the
  // foreground notification.
  if (!hasOpenCandidates() && onAllValidated) {
    onAllValidated();
  }
});
