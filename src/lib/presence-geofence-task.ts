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

  try {
    // Headless wakes can hit before supabase-js finishes restoring the
    // session from SecureStore. Explicitly await so the RPC carries a token.
    const { data: sessionData } = await supabase.auth.getSession();
    if (!sessionData?.session) {
      trace('presence.geofence', 'task: no session, enqueue for replay');
      await enqueueGeoEvent({
        activity_id: activityId,
        lng: region.longitude,
        lat: region.latitude,
        captured_at: capturedAt,
      });
      return;
    }

    const { error } = await supabase.rpc('confirm_presence_via_geo' as 'join_activity', {
      p_activity_id: activityId,
      p_lng: region.longitude,
      p_lat: region.latitude,
      p_skip_push: true,
    } as unknown as { p_activity_id: string });

    if (!error) {
      trace('presence.geofence', 'task: RPC succeeded, flipping slot to confirmée');
      // RPC succeeded → flip the slot to "Présence confirmée".
      Notifications.scheduleNotificationAsync({
        identifier: slotId,
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
      lng: region.longitude,
      lat: region.latitude,
      captured_at: capturedAt,
    });
  } catch (err) {
    trace('presence.geofence', 'task: RPC threw, enqueue for replay', {
      message: err instanceof Error ? err.message : String(err),
    });
    await enqueueGeoEvent({
      activity_id: activityId,
      lng: region.longitude,
      lat: region.latitude,
      captured_at: capturedAt,
    });
  }
});
