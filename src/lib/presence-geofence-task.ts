import * as TaskManager from 'expo-task-manager';
import * as Location from 'expo-location';
import * as Notifications from 'expo-notifications';
import { supabase } from '@/services/supabase';
import { enqueueGeoEvent } from './presence-offline-cache';

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
  if (error) return;
  const { eventType, region } = (data ?? {}) as GeofenceEvent;
  if (eventType !== Location.GeofencingEventType.Enter) return;
  const id = region?.identifier ?? '';
  if (!id.startsWith('presence:')) return;

  const activityId = id.split(':')[1];
  if (!activityId) return;

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
    } as unknown as { p_activity_id: string });

    if (!error) {
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

    // Network/transport errors → cache for replay; the offline flusher
    // updates the slot to "confirmée" once the replay succeeds.
    // Server-side rejections ("Operation not permitted") are terminal —
    // gate is the same on retry, slot stays at "détectée".
    if (!(error.message ?? '').includes('Operation not permitted')) {
      await enqueueGeoEvent({
        activity_id: activityId,
        lng: region.longitude,
        lat: region.latitude,
        captured_at: capturedAt,
      });
    }
  } catch {
    await enqueueGeoEvent({
      activity_id: activityId,
      lng: region.longitude,
      lat: region.latitude,
      captured_at: capturedAt,
    });
  }
});
