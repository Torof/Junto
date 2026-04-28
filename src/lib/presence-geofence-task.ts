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

  // Local notification on every Enter event. Stable identifier so a second
  // Enter for the same activity REPLACES the existing OS notif rather than
  // stacking a fresh modal. Fires regardless of RPC outcome — the user
  // wants the visible signal even when they're offline (RPC will replay
  // through presence-offline-cache once network returns).
  Notifications.scheduleNotificationAsync({
    identifier: `presence-arrival-${activityId}`,
    content: {
      title: 'Présence confirmée',
      body: 'Tu es à proximité de ton activité.',
      data: { activity_id: activityId, type: 'presence_confirmed' },
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

    // Network/transport errors → cache for replay. Server-side rejections
    // ("Operation not permitted") are terminal — the gate will be the same
    // on retry, so don't queue.
    if (error && !(error.message ?? '').includes('Operation not permitted')) {
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
