import AsyncStorage from '@react-native-async-storage/async-storage';
import NetInfo from '@react-native-community/netinfo';
import { supabase } from '@/services/supabase';

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

    for (const event of queue) {
      try {
        const { error } = await supabase.rpc('confirm_presence_via_geo' as 'join_activity', {
          p_activity_id: event.activity_id,
          p_lng: event.lng,
          p_lat: event.lat,
          p_captured_at: event.captured_at,
        } as unknown as { p_activity_id: string });

        // Success → drop. Server-side rejection ("Operation not permitted")
        // also drops the entry: it means the captured_at is out of window,
        // distance is wrong, presence is already set, or the user lost
        // accepted status. None of those are recoverable by retrying.
        if (!error || (error.message ?? '').includes('Operation not permitted')) {
          await dropForActivity(event.activity_id);
        }
        // Any other error (network, 5xx) — leave it for the next flush.
      } catch {
        // Network or transport error — leave entry in place.
      }
    }
  } finally {
    flushing = false;
  }
}
