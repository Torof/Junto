import AsyncStorage from '@react-native-async-storage/async-storage';
import NetInfo from '@react-native-community/netinfo';
import * as Notifications from 'expo-notifications';
import { supabase } from '@/services/supabase';
import { trace } from '@/lib/sentry';

const STORAGE_KEY = '@junto/presence-offline-queue';

export interface CachedGeoEvent {
  activity_id: string;
  lng: number;
  lat: number;
  captured_at: string;
}

async function readQueue(): Promise<CachedGeoEvent[]> {
  try {
    const raw = await AsyncStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? (parsed as CachedGeoEvent[]) : [];
  } catch {
    return [];
  }
}

async function writeQueue(items: CachedGeoEvent[]): Promise<void> {
  try {
    await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(items));
  } catch {
    // best-effort
  }
}

export async function enqueueGeoEvent(event: CachedGeoEvent): Promise<void> {
  const queue = await readQueue();
  // Dedup: one cached event per activity (the first in-zone moment is enough).
  if (queue.some((e) => e.activity_id === event.activity_id)) return;
  queue.push(event);
  await writeQueue(queue);
  trace('presence.offline', 'enqueued geo event', { queue_size: queue.length });
}

async function dropForActivity(activityId: string): Promise<void> {
  const queue = await readQueue();
  await writeQueue(queue.filter((e) => e.activity_id !== activityId));
}

let flushing = false;

export async function flushOfflineGeoQueue(): Promise<void> {
  if (flushing) return;
  const net = await NetInfo.fetch();
  if (!net.isConnected || net.isInternetReachable === false) return;

  flushing = true;
  try {
    const { data: sessionData } = await supabase.auth.getSession();
    if (!sessionData?.session) return;

    const queue = await readQueue();
    if (queue.length === 0) return;

    trace('presence.offline', 'flush starting', { queue_size: queue.length });

    for (const event of queue) {
      try {
        const { error } = await supabase.rpc('confirm_presence_via_geo' as 'join_activity', {
          p_activity_id: event.activity_id,
          p_lng: event.lng,
          p_lat: event.lat,
          p_captured_at: event.captured_at,
          p_skip_push: true,
        } as unknown as { p_activity_id: string });

        if (!error) {
          trace('presence.offline', 'replay succeeded, flipping slot to confirmée');
          // Replay succeeded → flip the OS notif slot from "détectée" (set
          // by the geofence task before going offline) to "confirmée".
          // Same identifier so the existing notif is replaced in place.
          Notifications.scheduleNotificationAsync({
            identifier: `presence-${event.activity_id}`,
            content: {
              title: 'Présence confirmée',
              body: 'Ta présence à cette activité est confirmée.',
              data: { activity_id: event.activity_id, type: 'presence_confirmed' },
              sound: true,
            },
            trigger: null,
          }).catch(() => {});
          await dropForActivity(event.activity_id);
        } else if ((error.message ?? '').includes('Operation not permitted')) {
          trace('presence.offline', 'replay rejected (terminal), dropping', {
            reason: error.message,
          });
          // Terminal server-side rejection (out of window, already
          // confirmed, etc.) — drop the entry. Slot stays at "détectée"
          // since we can't claim a confirmation that didn't happen.
          await dropForActivity(event.activity_id);
        } else {
          trace('presence.offline', 'replay failed (non-terminal), keeping in queue', {
            reason: error.message,
          });
        }
      } catch (err) {
        trace('presence.offline', 'replay threw, keeping in queue', {
          message: err instanceof Error ? err.message : String(err),
        });
      }
    }
  } finally {
    flushing = false;
  }
}
