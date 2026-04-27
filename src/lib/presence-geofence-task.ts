import * as TaskManager from 'expo-task-manager';
import * as Location from 'expo-location';
import * as Notifications from 'expo-notifications';
import { supabase } from '@/services/supabase';

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

  try {
    // Refresh the session if necessary; supabase-js auto-handles token refresh
    // on rpc() calls, so we just call directly.
    const { error: rpcErr } = await supabase.rpc('confirm_presence_via_geo' as 'join_activity', {
      p_activity_id: activityId,
      p_lng: region.longitude,
      p_lat: region.latitude,
    } as unknown as { p_activity_id: string });

    // Either way (success or "already confirmed" / window closed), surface a
    // local notification so the user knows their crossing was registered.
    if (!rpcErr) {
      await Notifications.scheduleNotificationAsync({
        content: {
          title: 'Présence confirmée',
          body: 'Tu es à proximité de ton activité.',
          data: { activity_id: activityId, type: 'presence_confirmed' },
          sound: true,
        },
        trigger: null,
      }).catch(() => {});
    }
  } catch {
    // Best-effort: failures are silent. The user still has the in-app paths.
  }
});
