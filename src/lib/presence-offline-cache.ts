import AsyncStorage from '@react-native-async-storage/async-storage';
import NetInfo from '@react-native-community/netinfo';
import * as Notifications from 'expo-notifications';
import { supabase } from '@/services/supabase';
import { trace } from '@/lib/sentry';

const STORAGE_KEY = '@junto/presence-offline-queue';

// Replay is only ever valid until starts_at + duration + 3h server-side
// (max duration 24h → worst case ~27h after capture). Anything older is
// dead weight that can never succeed — purge it at flush time.
const MAX_EVENT_AGE_MS = 30 * 60 * 60 * 1000;
// Two events for the same activity captured within this span are the same
// in-zone episode — keep only the first. Distinct episodes (leave + come
// back later) are kept separately so an early, pre-window Enter can never
// shadow the real in-window one.
const EPISODE_DEDUP_MS = 10 * 60_000;
const MAX_EVENTS_PER_ACTIVITY = 3;

export interface CachedGeoEvent {
  activity_id: string;
  lng: number;
  lat: number;
  captured_at: string;
}

/**
 * Server-side rejections that no retry can ever fix: auth/ownership
 * failures ("Operation not permitted") and the coded presence gates
 * (junto.presence_window_closed, junto.presence_too_far,
 * junto.presence_unavailable, junto.presence_token_window_closed).
 * Anything else (network hiccup, 5xx) is worth keeping for replay.
 */
export function isTerminalPresenceRejection(message: string | null | undefined): boolean {
  const msg = message ?? '';
  return msg.includes('Operation not permitted') || msg.includes('junto.presence_');
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
  const ts = new Date(event.captured_at).getTime();
  const sameActivity = queue.filter((e) => e.activity_id === event.activity_id);
  if (sameActivity.some((e) => Math.abs(new Date(e.captured_at).getTime() - ts) < EPISODE_DEDUP_MS)) {
    return;
  }
  if (sameActivity.length >= MAX_EVENTS_PER_ACTIVITY) {
    const oldest = sameActivity.reduce((a, b) => (a.captured_at < b.captured_at ? a : b));
    const idx = queue.indexOf(oldest);
    if (idx >= 0) queue.splice(idx, 1);
  }
  queue.push(event);
  await writeQueue(queue);
  trace('presence.offline', 'enqueued geo event', { queue_size: queue.length });
}

async function dropForActivity(activityId: string): Promise<void> {
  const queue = await readQueue();
  await writeQueue(queue.filter((e) => e.activity_id !== activityId));
}

async function dropEvent(event: CachedGeoEvent): Promise<void> {
  const queue = await readQueue();
  await writeQueue(
    queue.filter((e) => !(e.activity_id === event.activity_id && e.captured_at === event.captured_at)),
  );
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

    let queue = await readQueue();
    const cutoff = Date.now() - MAX_EVENT_AGE_MS;
    const fresh = queue.filter((e) => new Date(e.captured_at).getTime() >= cutoff);
    if (fresh.length !== queue.length) {
      trace('presence.offline', 'purged stale events', { purged: queue.length - fresh.length });
      await writeQueue(fresh);
      queue = fresh;
    }
    if (queue.length === 0) return;

    trace('presence.offline', 'flush starting', { queue_size: queue.length });

    const confirmedActivities = new Set<string>();
    for (const event of queue) {
      if (confirmedActivities.has(event.activity_id)) continue;
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
          confirmedActivities.add(event.activity_id);
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
        } else if (isTerminalPresenceRejection(error.message)) {
          trace('presence.offline', 'replay rejected (terminal), dropping event', {
            reason: error.message,
          });
          // Terminal server-side rejection — drop THIS event only: another
          // episode for the same activity (captured inside the window) may
          // still succeed. Slot stays at "détectée" since we can't claim a
          // confirmation that didn't happen.
          await dropEvent(event);
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
