import { useEffect } from 'react';
import * as Location from 'expo-location';
import { AppState } from 'react-native';
import { supabase } from '@/services/supabase';
import { PRESENCE_GEOFENCE_TASK } from '@/lib/presence-geofence-task';
import { trace } from '@/lib/sentry';
import { distanceMeters } from '@/utils/geo';

interface ActiveActivity {
  activity_id: string;
  start_lng: number | null;
  start_lat: number | null;
  meeting_lng: number | null;
  meeting_lat: number | null;
  end_lng: number | null;
  end_lat: number | null;
  starts_at: string;
}

// Bumped from 150m to 300m — mountain/canyon GPS uncertainty regularly hits
// 50–100m, and a tight radius means the OS rarely gets a confident enough
// transition to fire Enter. 300m gives the OS room to detect crossings while
// still being tight enough that the server-side time-window gate prevents
// false confirmations in adjacent zones.
const RADIUS_M = 300;
// iOS hard-caps at 20 regions per app. We pick one location per activity (the
// meeting point if set, otherwise start), then trim to the closest 20 by
// starts_at proximity.
const MAX_REGIONS = 20;
// Reject GPS samples too imprecise to safely auto-confirm. With the 300m
// radius we tolerate up to ~100m accuracy (still inside the radius even if
// the user is at the edge).
const ACCURACY_THRESHOLD_M = 100;
// Foreground watcher window — when the app is foregrounded inside this
// window around starts_at, we stream high-accuracy fixes for up to 60s to
// catch users whose cold-start position is stale.
const WINDOW_BEFORE_MS = 15 * 60_000;
const WINDOW_AFTER_MS = 15 * 60_000;
const WATCHER_DURATION_MS = 60_000;

async function fetchCandidates(): Promise<ActiveActivity[]> {
  const { data } = (await supabase.rpc('get_my_active_presence_activities' as 'accept_tos')) as unknown as {
    data: ActiveActivity[] | null;
  };
  const candidates = data ?? [];
  candidates.sort((a, b) => new Date(a.starts_at).getTime() - new Date(b.starts_at).getTime());
  return candidates;
}

function toRegions(candidates: ActiveActivity[]): Location.LocationRegion[] {
  const regions: Location.LocationRegion[] = [];
  for (const a of candidates) {
    if (regions.length >= MAX_REGIONS) break;
    let lng = a.meeting_lng;
    let lat = a.meeting_lat;
    if (lng == null || lat == null) {
      lng = a.start_lng;
      lat = a.start_lat;
    }
    if (lng == null || lat == null) continue;
    regions.push({
      identifier: `presence:${a.activity_id}:${lat},${lng}`,
      latitude: lat,
      longitude: lng,
      radius: RADIUS_M,
      notifyOnEnter: true,
      notifyOnExit: false,
    });
  }
  return regions;
}

// Initial-state check — runs whenever the app comes into focus, regardless of
// background-location permission. The Enter event from the OS only fires on a
// genuine outside→inside transition, so a user who's already on-site at app
// open would never get auto-confirmed. We force a fresh high-accuracy fix
// (Accuracy.High triggers a real GPS lock instead of returning a cached
// network/cell fix) and call the RPC directly for any region the user is
// already inside; server gates on time window so calls outside T-15min..T+15min
// are no-ops.
async function initialStateCheck(regions: Location.LocationRegion[]): Promise<void> {
  if (regions.length === 0) return;

  const fg = await Location.getForegroundPermissionsAsync();
  if (fg.status !== 'granted') {
    trace('presence.geofence', 'initial-state skipped: no foreground permission');
    return;
  }

  let pos: Location.LocationObject;
  try {
    pos = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.High });
  } catch {
    trace('presence.geofence', 'initial-state skipped: getCurrentPositionAsync threw');
    return;
  }

  if (pos.coords.accuracy != null && pos.coords.accuracy > ACCURACY_THRESHOLD_M) {
    trace('presence.geofence', 'initial-state skipped: accuracy too low', {
      accuracy_m: Math.round(pos.coords.accuracy),
    });
    return;
  }

  for (const region of regions) {
    const d = distanceMeters(pos.coords.latitude, pos.coords.longitude, region.latitude, region.longitude);
    if (d > region.radius) continue;

    const activityId = String(region.identifier ?? '').split(':')[1];
    if (!activityId) continue;

    trace('presence.geofence', 'initial-state in zone, calling RPC', {
      distance_m: Math.round(d),
    });

    try {
      const { error } = await supabase.rpc('confirm_presence_via_geo' as 'join_activity', {
        p_activity_id: activityId,
        p_lng: pos.coords.longitude,
        p_lat: pos.coords.latitude,
      } as unknown as { p_activity_id: string });
      if (error) {
        trace('presence.geofence', 'initial-state RPC rejected', { reason: error.message });
      } else {
        trace('presence.geofence', 'initial-state RPC succeeded');
      }
    } catch (err) {
      trace('presence.geofence', 'initial-state RPC threw', {
        message: err instanceof Error ? err.message : String(err),
      });
    }
  }
}

// Foreground watcher — when the app is in the foreground and at least one
// candidate activity is inside its presence window (T-15min..T+15min), we
// subscribe to high-accuracy position updates for up to 60s. This catches
// users whose initial cold-start fix was too coarse to pass the threshold:
// the watcher waits for GPS to lock in, then confirms on the first usable
// in-zone sample. Stops on first successful RPC or after the duration.
let activeWatcher: { remove: () => void } | null = null;
async function runForegroundWatcher(candidates: ActiveActivity[], regions: Location.LocationRegion[]): Promise<void> {
  if (regions.length === 0) return;

  const now = Date.now();
  const inWindow = candidates.filter((a) => {
    const t = new Date(a.starts_at).getTime();
    return t - WINDOW_BEFORE_MS <= now && now <= t + WINDOW_AFTER_MS;
  });
  if (inWindow.length === 0) return;

  // Build a quick lookup of the regions corresponding to in-window activities.
  const activeIds = new Set(inWindow.map((a) => a.activity_id));
  const activeRegions = regions.filter((r) => {
    const id = String(r.identifier ?? '').split(':')[1];
    return id && activeIds.has(id);
  });
  if (activeRegions.length === 0) return;

  const fg = await Location.getForegroundPermissionsAsync();
  if (fg.status !== 'granted') return;

  // Don't stack watchers — if one is already running, let it finish.
  if (activeWatcher) return;

  trace('presence.geofence', 'foreground watcher started', { regions: activeRegions.length });

  const confirmed = new Set<string>();
  let timedOut = false;

  const sub = await Location.watchPositionAsync(
    {
      accuracy: Location.Accuracy.High,
      timeInterval: 5_000,
      distanceInterval: 10,
    },
    async (pos) => {
      if (timedOut) return;
      if (pos.coords.accuracy != null && pos.coords.accuracy > ACCURACY_THRESHOLD_M) return;

      for (const region of activeRegions) {
        const activityId = String(region.identifier ?? '').split(':')[1];
        if (!activityId || confirmed.has(activityId)) continue;

        const d = distanceMeters(pos.coords.latitude, pos.coords.longitude, region.latitude, region.longitude);
        if (d > region.radius) continue;

        confirmed.add(activityId);
        trace('presence.geofence', 'foreground watcher in zone, calling RPC', {
          distance_m: Math.round(d),
          accuracy_m: pos.coords.accuracy != null ? Math.round(pos.coords.accuracy) : null,
        });

        try {
          const { error } = await supabase.rpc('confirm_presence_via_geo' as 'join_activity', {
            p_activity_id: activityId,
            p_lng: pos.coords.longitude,
            p_lat: pos.coords.latitude,
          } as unknown as { p_activity_id: string });
          if (error) {
            trace('presence.geofence', 'foreground watcher RPC rejected', { reason: error.message });
          } else {
            trace('presence.geofence', 'foreground watcher RPC succeeded');
          }
        } catch (err) {
          trace('presence.geofence', 'foreground watcher RPC threw', {
            message: err instanceof Error ? err.message : String(err),
          });
        }
      }

      if (confirmed.size >= activeRegions.length) {
        sub.remove();
        activeWatcher = null;
        trace('presence.geofence', 'foreground watcher stopped: all confirmed');
      }
    }
  );

  activeWatcher = sub;
  setTimeout(() => {
    timedOut = true;
    sub.remove();
    if (activeWatcher === sub) activeWatcher = null;
    trace('presence.geofence', 'foreground watcher stopped: timeout');
  }, WATCHER_DURATION_MS);
}

async function refreshGeofences(): Promise<void> {
  const candidates = await fetchCandidates();
  const regions = toRegions(candidates);

  // Initial-state check needs only foreground permission. Run it before
  // anything else so users with "While Using" still get the on-app-open
  // auto-confirmation when they're already on-site.
  await initialStateCheck(regions);

  // Foreground watcher kicks in when the user is inside a presence window
  // and the cold-start fix wasn't precise enough — keeps polling until GPS
  // locks. Runs in parallel with the OS-level region monitor below.
  runForegroundWatcher(candidates, regions);

  // OS-level region monitoring requires "Always" / background permission.
  const bg = await Location.getBackgroundPermissionsAsync();
  if (bg.status !== 'granted') {
    const running = await Location.hasStartedGeofencingAsync(PRESENCE_GEOFENCE_TASK).catch(() => false);
    if (running) {
      await Location.stopGeofencingAsync(PRESENCE_GEOFENCE_TASK).catch(() => {});
      trace('presence.geofence', 'stopped: no background permission');
    }
    return;
  }

  if (regions.length === 0) {
    const running = await Location.hasStartedGeofencingAsync(PRESENCE_GEOFENCE_TASK).catch(() => false);
    if (running) {
      await Location.stopGeofencingAsync(PRESENCE_GEOFENCE_TASK).catch(() => {});
      trace('presence.geofence', 'stopped: no candidate activities');
    }
    return;
  }

  try {
    await Location.startGeofencingAsync(PRESENCE_GEOFENCE_TASK, regions);
    trace('presence.geofence', 'registered regions', { count: regions.length });
  } catch (err) {
    trace('presence.geofence', 'registration threw', {
      message: err instanceof Error ? err.message : String(err),
    });
  }
}

/**
 * Background geofencing. Registers regions for each upcoming presence-required
 * activity the user has joined; the OS wakes the app on entry and runs the
 * registered TaskManager task, which calls confirm_presence_via_geo.
 *
 * Active only when the user has granted "Always" location permission. The
 * initial-state check (auto-confirm on app open if already in zone) runs
 * with foreground permission alone, since it doesn't rely on the OS region
 * monitor.
 *
 * On hook teardown — including sign-out, when the auth layout unmounts —
 * any registered regions are unregistered so they don't fan out wakes for a
 * signed-out user.
 */
export function usePresenceGeofences(enabled: boolean) {
  useEffect(() => {
    if (!enabled) return;
    refreshGeofences();
    const sub = AppState.addEventListener('change', (next) => {
      if (next === 'active') refreshGeofences();
    });
    return () => {
      sub.remove();
      if (activeWatcher) {
        activeWatcher.remove();
        activeWatcher = null;
      }
      Location.stopGeofencingAsync(PRESENCE_GEOFENCE_TASK).catch(() => {});
      trace('presence.geofence', 'stopped: hook unmounted');
    };
  }, [enabled]);
}
