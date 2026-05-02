import * as TaskManager from 'expo-task-manager';
import * as Location from 'expo-location';
import * as Notifications from 'expo-notifications';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { supabase } from '@/services/supabase';
import { trace, captureInfo } from './sentry';
import { distanceMeters } from '@/utils/geo';

// Task name registered at module-load time. Imported from app/_layout so
// the OS can find this task definition when it spawns the headless JS
// runtime to deliver location updates.
export const PRESENCE_LOCATION_TASK = 'junto.presence-location';

// AsyncStorage keys. Module-level Set state was unreliable — Sentry
// breadcrumbs showed the task firing every ~10s on the same candidate
// after a successful RPC, which means the in-memory validated Set was
// getting reset between callbacks. Persisting to disk is robust against
// any JS runtime / process recycling the OS does to the foreground
// service.
const VALIDATED_KEY_PREFIX = 'presence:fg:validated:';
const validatedKey = (id: string) => `${VALIDATED_KEY_PREFIX}${id}`;

async function isValidated(activityId: string): Promise<boolean> {
  try {
    const v = await AsyncStorage.getItem(validatedKey(activityId));
    return v === '1';
  } catch {
    return false;
  }
}

async function markValidated(activityId: string): Promise<void> {
  try {
    await AsyncStorage.setItem(validatedKey(activityId), '1');
  } catch {
    // best-effort
  }
}

export async function clearValidatedFor(activityIds: string[]): Promise<void> {
  if (activityIds.length === 0) return;
  try {
    await AsyncStorage.multiRemove(activityIds.map(validatedKey));
  } catch {
    // best-effort
  }
}

// Mirrors the geofence task / foreground watcher.
const RADIUS_M = 300;
const ACCURACY_THRESHOLD_M = 100;

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

// Module-level candidate list. Set by the service when it starts. The
// validated state is persisted separately to AsyncStorage (see above) so
// it survives JS runtime resets between location callbacks.
let candidates: PresenceCandidate[] = [];

export function setLocationTaskCandidates(next: PresenceCandidate[]): void {
  candidates = next.slice();
}

export function getLocationTaskCandidates(): PresenceCandidate[] {
  return candidates.slice();
}

export function clearLocationTaskCandidates(): void {
  candidates = [];
}

interface LocationTaskPayload {
  locations?: Location.LocationObject[];
}

TaskManager.defineTask(PRESENCE_LOCATION_TASK, async ({ data, error }) => {
  if (error) {
    trace('presence.location', 'task fired with error', { reason: String(error) });
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

  // Sentry confirmed the runtime can recycle between callbacks (validated
  // set was empty after a successful RPC, causing perpetual re-validation
  // and a foreground service that never stopped). Read validated flags
  // from AsyncStorage on every fire, write them on RPC success.
  let openCount = 0;
  for (const candidate of candidates) {
    if (await isValidated(candidate.activity_id)) continue;

    const d = distanceMeters(
      fix.coords.latitude,
      fix.coords.longitude,
      candidate.lat,
      candidate.lng,
    );
    if (d > RADIUS_M) {
      openCount++;
      continue;
    }

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
        await markValidated(candidate.activity_id);
        // Local notif transition mirrors the geofence task path.
        const slotId = `presence-${candidate.activity_id}`;
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
      // returns success. Any other 'Operation not permitted' here means
      // we're outside the validation window or some auth chain rejected
      // — terminal, mark validated so we stop checking.
      if ((rpcError.message ?? '').includes('Operation not permitted')) {
        await markValidated(candidate.activity_id);
        trace('presence.location', 'RPC rejected (terminal), skipping further checks', {
          reason: rpcError.message,
        });
      } else {
        openCount++;
        trace('presence.location', 'RPC failed (transient), will retry on next sample', {
          reason: rpcError.message,
        });
      }
    } catch (err) {
      openCount++;
      trace('presence.location', 'RPC threw, will retry on next sample', {
        message: err instanceof Error ? err.message : String(err),
      });
    }
  }

  // All candidates settled — stop the foreground service ourselves. The
  // service module's onAllValidated callback was unreliable in headless
  // contexts (module-level closure may be cleared on runtime reset). The
  // OS-level stop call from inside the task is robust and removes the
  // persistent foregroundService notification.
  if (openCount === 0 && candidates.length > 0) {
    captureInfo('presence.location', 'all validated, stopping service');
    await Location.stopLocationUpdatesAsync(PRESENCE_LOCATION_TASK).catch(() => {});
  }
});
