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

// Serialize every read-modify-write on the queue WITHIN this JS context.
// enqueueGeoEvent runs from the OS geofence task while flush runs off
// NetInfo/AppState — an unlocked interleaving (both read, both write)
// silently drops whichever event the losing write didn't know about.
let queueChain: Promise<unknown> = Promise.resolve();
function withQueueLock<T>(fn: () => Promise<T>): Promise<T> {
  const run = queueChain.then(fn, fn);
  queueChain = run.catch(() => {});
  return run;
}

// The queue document carries a version stamp: the module mutex above only
// serializes one JS runtime, but a headless geofence wake (app killed) and
// the foreground app are two runtimes with two independent mutexes. The
// re-read version check before writing shrinks the cross-context
// lost-update window from "the whole RPC loop" to microseconds.
interface QueueDoc {
  v: number;
  items: CachedGeoEvent[];
}

async function readQueueDoc(): Promise<QueueDoc> {
  try {
    const raw = await AsyncStorage.getItem(STORAGE_KEY);
    if (!raw) return { v: 0, items: [] };
    const parsed = JSON.parse(raw);
    // Legacy format: a bare array (pre-versioning bundles).
    if (Array.isArray(parsed)) return { v: 0, items: parsed as CachedGeoEvent[] };
    if (parsed && Array.isArray(parsed.items)) {
      return { v: Number(parsed.v) || 0, items: parsed.items as CachedGeoEvent[] };
    }
    return { v: 0, items: [] };
  } catch {
    return { v: 0, items: [] };
  }
}

// Optimistic-concurrency mutation. `fn` returns the new items array, or
// null for "no change needed". Retries on version conflict; the LAST
// attempt writes unconditionally (last-writer-wins) — for our callers,
// losing the mutation outright (a measured presence event, a terminal
// drop) is strictly worse than the microsecond cross-context overwrite
// the unconditional write risks. `fn` must be pure over its input.
type MutateOutcome =
  | { outcome: 'written'; items: CachedGeoEvent[] }
  | { outcome: 'unchanged'; items: CachedGeoEvent[] };

async function mutateQueue(
  fn: (items: CachedGeoEvent[]) => CachedGeoEvent[] | null,
): Promise<MutateOutcome> {
  const ATTEMPTS = 4;
  for (let attempt = 0; attempt < ATTEMPTS; attempt++) {
    const doc = await readQueueDoc();
    const next = fn(doc.items.slice());
    if (next === null) return { outcome: 'unchanged', items: doc.items };
    const lastAttempt = attempt === ATTEMPTS - 1;
    if (!lastAttempt) {
      const check = await readQueueDoc();
      if (check.v !== doc.v) continue;
    } else {
      trace('presence.offline', 'queue CAS exhausted, writing last-writer-wins');
    }
    try {
      await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify({ v: doc.v + 1, items: next }));
    } catch {
      // best-effort
    }
    return { outcome: 'written', items: next };
  }
  // Unreachable (last attempt always writes) — satisfies the type checker.
  return { outcome: 'unchanged', items: [] };
}

export function enqueueGeoEvent(event: CachedGeoEvent): Promise<void> {
  return withQueueLock(async () => {
    const result = await mutateQueue((items) => {
      const ts = new Date(event.captured_at).getTime();
      const sameActivity = items.filter((e) => e.activity_id === event.activity_id);
      if (sameActivity.some((e) => Math.abs(new Date(e.captured_at).getTime() - ts) < EPISODE_DEDUP_MS)) {
        return null;
      }
      if (sameActivity.length >= MAX_EVENTS_PER_ACTIVITY) {
        const oldest = sameActivity.reduce((a, b) => (a.captured_at < b.captured_at ? a : b));
        const idx = items.indexOf(oldest);
        if (idx >= 0) items.splice(idx, 1);
      }
      items.push(event);
      return items;
    });
    if (result.outcome === 'written') {
      trace('presence.offline', 'enqueued geo event', { queue_size: result.items.length });
    }
  });
}

function dropForActivity(activityId: string): Promise<void> {
  return withQueueLock(async () => {
    await mutateQueue((items) => items.filter((e) => e.activity_id !== activityId));
  });
}

function dropEvent(event: CachedGeoEvent): Promise<void> {
  return withQueueLock(async () => {
    await mutateQueue((items) =>
      items.filter((e) => !(e.activity_id === event.activity_id && e.captured_at === event.captured_at)),
    );
  });
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

    const queue = await withQueueLock(async () => {
      const cutoff = Date.now() - MAX_EVENT_AGE_MS;
      const result = await mutateQueue((items) => {
        const fresh = items.filter((e) => new Date(e.captured_at).getTime() >= cutoff);
        if (fresh.length === items.length) return null;
        trace('presence.offline', 'purged stale events', { purged: items.length - fresh.length });
        return fresh;
      });
      return result.items;
    });
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
          // Replay succeeded → dismiss the "détectée" notif and post
          // "confirmée" under a DISTINCT identifier — same rationale as the
          // geofence task: re-scheduling on the same identifier is a silent
          // in-place update on Android (no sound, invisible if already
          // dismissed), and this is the moment the user most needs to learn
          // their presence finally went through. Cancel a still-pending
          // deferred détectée too (dismiss only clears the tray).
          await Notifications.cancelScheduledNotificationAsync(`presence-${event.activity_id}`).catch(() => {});
          await Notifications.cancelScheduledNotificationAsync(`presence-${event.activity_id}-pending`).catch(() => {});
          await Notifications.dismissNotificationAsync(`presence-${event.activity_id}`).catch(() => {});
          Notifications.scheduleNotificationAsync({
            identifier: `presence-${event.activity_id}-confirmed`,
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
