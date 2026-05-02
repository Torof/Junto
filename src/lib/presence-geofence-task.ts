import * as TaskManager from 'expo-task-manager';
import * as Location from 'expo-location';
import * as Notifications from 'expo-notifications';
import { supabase } from '@/services/supabase';
import { enqueueGeoEvent } from './presence-offline-cache';
import { trace } from './sentry';

// Task name must be a constant defined at the top of a module that's imported
// at app startup (see _layout). Expo TaskManager requires the task to be
// registered before TaskManager.startGeofencingAsync runs.
export const PRESENCE_GEOFENCE_TASK = 'junto.presence-geofence';

// Headless GPS fix budget. The OS gives the task ~30s total; we cap the GPS
// wait at 8s so there's room for the RPC + slot updates. If we don't get a
// fresh fix in time, we enqueue for replay rather than guess from the
// region center (which would let stale-fused-location false positives
// silently auto-confirm presence).
const FRESH_FIX_TIMEOUT_MS = 8_000;
// Reject GPS samples too imprecise to safely auto-confirm. Mirrors the
// foreground watcher's threshold and stays inside the 300m server-side
// distance gate even at the radius edge.
const ACCURACY_THRESHOLD_M = 100;

async function getFreshFix(): Promise<Location.LocationObject | null> {
  try {
    return await Promise.race([
      Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.High }),
      new Promise<null>((resolve) => setTimeout(() => resolve(null), FRESH_FIX_TIMEOUT_MS)),
    ]);
  } catch {
    return null;
  }
}

interface GeofenceEvent {
  eventType: Location.GeofencingEventType;
  region: Location.LocationRegion & { identifier?: string };
}

// Region identifier convention: `presence:<activity_id>:<lat>,<lng>`
// We only act on Enter events.
TaskManager.defineTask(PRESENCE_GEOFENCE_TASK, async ({ data, error }) => {
  if (error) {
    trace('presence.geofence', 'task fired with error', { message: String(error) });
    return;
  }
  const { eventType, region } = (data ?? {}) as GeofenceEvent;
  if (eventType !== Location.GeofencingEventType.Enter) return;
  const id = region?.identifier ?? '';
  if (!id.startsWith('presence:')) return;

  const activityId = id.split(':')[1];
  if (!activityId) return;

  trace('presence.geofence', 'task: Enter event');

  // First state: "Présence détectée". Same identifier across both states so
  // the OS slot is updated in place — never two notifs at once.
  const slotId = `presence-${activityId}`;
  Notifications.scheduleNotificationAsync({
    identifier: slotId,
    content: {
      title: 'Présence détectée',
      body: "Tu es à portée de l'activité, valide ta présence.",
      data: { activity_id: activityId, type: 'presence_detected' },
      sound: true,
    },
    trigger: null,
  }).catch(() => {});

  const capturedAt = new Date().toISOString();

  // Fetch a fresh high-accuracy GPS fix instead of trusting the region
  // center. Background-fused-location estimates can be minutes stale and
  // off by hundreds of meters (Doze + cell/wifi-only signals), so the OS
  // can fire Enter from a position that isn't actually inside the zone.
  // Sending the region center to the server bypasses the 150m distance
  // gate (distance to itself = 0) — a real GPS fix here lets the server
  // catch false positives.
  const fix = await getFreshFix();

  if (!fix) {
    trace('presence.geofence', 'task: no fresh fix, enqueue for replay');
    await enqueueGeoEvent({
      activity_id: activityId,
      lng: region.longitude,
      lat: region.latitude,
      captured_at: capturedAt,
    });
    return;
  }

  if (fix.coords.accuracy != null && fix.coords.accuracy > ACCURACY_THRESHOLD_M) {
    trace('presence.geofence', 'task: fix too coarse, enqueue for replay', {
      accuracy_m: Math.round(fix.coords.accuracy),
    });
    await enqueueGeoEvent({
      activity_id: activityId,
      lng: region.longitude,
      lat: region.latitude,
      captured_at: capturedAt,
    });
    return;
  }

  try {
    // Headless wakes can hit before supabase-js finishes restoring the
    // session from SecureStore. Explicitly await so the RPC carries a token.
    const { data: sessionData } = await supabase.auth.getSession();
    if (!sessionData?.session) {
      trace('presence.geofence', 'task: no session, enqueue for replay');
      await enqueueGeoEvent({
        activity_id: activityId,
        lng: fix.coords.longitude,
        lat: fix.coords.latitude,
        captured_at: capturedAt,
      });
      return;
    }

    const { error } = await supabase.rpc('confirm_presence_via_geo' as 'join_activity', {
      p_activity_id: activityId,
      p_lng: fix.coords.longitude,
      p_lat: fix.coords.latitude,
      p_skip_push: true,
    } as unknown as { p_activity_id: string });

    if (!error) {
      trace('presence.geofence', 'task: RPC succeeded, replacing détectée with confirmée');
      // Dismiss the détectée notif and schedule confirmée under a DISTINCT
      // identifier. Re-scheduling on the same identifier is treated as an
      // update on Android — silent, no sound, sometimes invisible if the
      // user already dismissed the first. Distinct id = fresh delivery
      // with sound, so the user actually perceives the validation step.
      await Notifications.dismissNotificationAsync(slotId).catch(() => {});
      Notifications.scheduleNotificationAsync({
        identifier: `${slotId}-confirmed`,
        content: {
          title: 'Présence confirmée',
          body: 'Ta présence à cette activité est confirmée.',
          data: { activity_id: activityId, type: 'presence_confirmed' },
          sound: true,
        },
        trigger: null,
      }).catch(() => {});
      return;
    }

    if ((error.message ?? '').includes('Operation not permitted')) {
      trace('presence.geofence', 'task: RPC rejected (terminal), slot stays at détectée', {
        reason: error.message,
      });
      return;
    }

    trace('presence.geofence', 'task: RPC failed (non-terminal), enqueue for replay', {
      reason: error.message,
    });
    await enqueueGeoEvent({
      activity_id: activityId,
      lng: fix.coords.longitude,
      lat: fix.coords.latitude,
      captured_at: capturedAt,
    });
  } catch (err) {
    trace('presence.geofence', 'task: RPC threw, enqueue for replay', {
      message: err instanceof Error ? err.message : String(err),
    });
    await enqueueGeoEvent({
      activity_id: activityId,
      lng: fix.coords.longitude,
      lat: fix.coords.latitude,
      captured_at: capturedAt,
    });
  }
});
