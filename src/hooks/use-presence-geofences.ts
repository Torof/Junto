import { useEffect } from 'react';
import * as Location from 'expo-location';
import * as Notifications from 'expo-notifications';
import { AppState } from 'react-native';
import { supabase } from '@/services/supabase';
import { PRESENCE_GEOFENCE_TASK } from '@/lib/presence-geofence-task';
import {
  startPresenceForegroundService,
  stopPresenceForegroundService,
} from '@/lib/presence-foreground-service';
import { trace, captureWarning } from '@/lib/sentry';
import { distanceMeters } from '@/utils/geo';

interface ActiveActivity {
  activity_id: string;
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
// iOS hard-caps at 20 regions per app. We pick one location per activity
// (the rendez-vous point), then trim to the closest 20 by starts_at proximity.
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

// Cache of currently-registered region identifiers. We compare this to
// the freshly-computed region set on each refresh and skip the
// startGeofencingAsync call if unchanged — avoids re-firing Enter events
// for regions the user is already inside (Android default behavior is
// INITIAL_TRIGGER_ENTER which would re-trigger our task on every
// re-registration).
let registeredRegionIds = new Set<string>();

// Returns null on RPC failure (offline, transient 5xx, session not yet
// restored) — distinct from a genuine empty candidate list. The caller must
// NOT tear down registered regions on null: ripping out geofences because
// the phone had no signal at app-open is exactly the outdoor scenario the
// offline replay exists for.
async function fetchCandidates(): Promise<ActiveActivity[] | null> {
  const { data, error } = (await supabase.rpc('get_my_active_presence_activities' as 'accept_tos')) as unknown as {
    data: ActiveActivity[] | null;
    error: { message?: string } | null;
  };
  if (error) {
    trace('presence.geofence', 'candidate fetch failed, keeping current regions', {
      reason: error.message ?? 'unknown',
    });
    return null;
  }
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
    if (lng == null || lat == null) continue;
    regions.push({
      // Trailing segment = starts_at in epoch ms; the geofence task uses it
      // to ignore Enter events fired before the server window opens.
      identifier: `presence:${a.activity_id}:${lat},${lng}:${new Date(a.starts_at).getTime()}`,
      latitude: lat,
      longitude: lng,
      radius: RADIUS_M,
      notifyOnEnter: true,
      notifyOnExit: false,
    });
  }
  return regions;
}

// The geofence task defers pre-window "détectée" notifs via a DATE trigger
// (see presence-geofence-task). Those pending notifs outlive their reason to
// exist when the user leaves the activity, the creator cancels it, or the
// presence gets confirmed — cancel any whose activity is no longer a
// candidate. Passing null (sign-out/teardown) cancels them all.
async function cleanupDeferredPresenceNotifs(candidates: ActiveActivity[] | null): Promise<void> {
  try {
    const scheduled = await Notifications.getAllScheduledNotificationsAsync();
    const live = new Set((candidates ?? []).map((a) => `presence-${a.activity_id}`));
    for (const n of scheduled) {
      if (!n.identifier.startsWith('presence-')) continue;
      // Strip state suffixes (-pending reminder) so a live activity's
      // reminder isn't reaped along with genuinely orphaned notifs.
      const baseId = n.identifier.replace(/-(pending|confirmed)$/, '');
      if (candidates !== null && live.has(baseId)) continue;
      await Notifications.cancelScheduledNotificationAsync(n.identifier).catch(() => {});
    }
  } catch {
    // best-effort
  }
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

  // Timebox the GPS lock (expo-location has no timeout option and
  // getCurrentPositionAsync can hang indefinitely indoors) — refreshes are
  // serialized, so an unbounded hang here would wedge ALL future region
  // registration for the JS session.
  let pos: Location.LocationObject | null;
  try {
    pos = await Promise.race([
      Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.High }),
      new Promise<null>((resolve) => setTimeout(() => resolve(null), 8_000)),
    ]);
  } catch {
    trace('presence.geofence', 'initial-state skipped: getCurrentPositionAsync threw');
    return;
  }
  if (!pos) {
    trace('presence.geofence', 'initial-state skipped: GPS lock timed out');
    return;
  }

  if (pos.coords.accuracy != null && pos.coords.accuracy > ACCURACY_THRESHOLD_M) {
    trace('presence.geofence', 'initial-state skipped: accuracy too low', {
      accuracy_m: Math.round(pos.coords.accuracy),
    });
    return;
  }

  const now = Date.now();
  for (const region of regions) {
    // Skip regions whose server window isn't open — the RPC would be a
    // guaranteed junto.presence_window_closed (candidates exist from T-2h).
    const startsAtMs = Number(String(region.identifier ?? '').split(':')[3]);
    if (Number.isFinite(startsAtMs) && (now < startsAtMs - WINDOW_BEFORE_MS || now > startsAtMs + WINDOW_AFTER_MS)) {
      continue;
    }

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
// Claimed synchronously before the awaits below — the `activeWatcher` null
// check alone races across getForegroundPermissionsAsync/watchPositionAsync
// and could stack two live GPS subscriptions.
let watcherStarting = false;
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

  // Don't stack watchers — if one is already running or mid-setup, let it finish.
  if (activeWatcher || watcherStarting) return;
  watcherStarting = true;

  try {
    const fg = await Location.getForegroundPermissionsAsync();
    if (fg.status !== 'granted') return;

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
  } finally {
    watcherStarting = false;
  }
}

// Android fires AppState 'active' in bursts (notification tap, permission
// dialogs, multi-resume). Each refresh does a network fetch + a GPS lock
// BEFORE registering regions — two interleaved runs could let the one with
// STALE candidates finish last, register its stale set and (via Android's
// INITIAL_TRIGGER_ENTER) re-fire Enter events. Serialize: one run at a
// time, a burst coalesces into a single trailing re-run.
let refreshInFlight = false;
let refreshQueued = false;
async function refreshGeofences(): Promise<void> {
  if (refreshInFlight) {
    refreshQueued = true;
    return;
  }
  refreshInFlight = true;
  try {
    await doRefreshGeofences();
  } finally {
    refreshInFlight = false;
    if (refreshQueued) {
      refreshQueued = false;
      void refreshGeofences();
    }
  }
}

async function doRefreshGeofences(): Promise<void> {
  const candidates = await fetchCandidates();
  if (candidates === null) return;
  const regions = toRegions(candidates);

  // Cancel deferred "détectée" notifs for activities that dropped out of
  // the candidate list (left, cancelled, already confirmed).
  void cleanupDeferredPresenceNotifs(candidates);

  // Initial-state check needs only foreground permission. Run it before
  // anything else so users with "While Using" still get the on-app-open
  // auto-confirmation when they're already on-site.
  await initialStateCheck(regions);

  // Foreground watcher kicks in when the user is inside a presence window
  // and the cold-start fix wasn't precise enough — keeps polling until GPS
  // locks. Runs in parallel with the OS-level region monitor below.
  void runForegroundWatcher(candidates, regions).catch(() => {});

  // Foreground service: when a presence window is active, start a
  // long-running foreground service that polls high-accuracy GPS and
  // validates as soon as the user enters the zone. This is the closed-
  // app path on aggressive Android OEMs (Samsung, Xiaomi, etc.) where
  // passive geofence Enter events aren't reliably delivered. Idempotent
  // — no-ops if already running. The service module fetches its own
  // candidate list, so we don't pass anything here.
  void startPresenceForegroundService();

  // OS-level region monitoring requires "Always" / background permission.
  const bg = await Location.getBackgroundPermissionsAsync();
  if (bg.status !== 'granted') {
    const running = await Location.hasStartedGeofencingAsync(PRESENCE_GEOFENCE_TASK).catch(() => false);
    if (running) {
      await Location.stopGeofencingAsync(PRESENCE_GEOFENCE_TASK).catch(() => {});
      // Purge the in-memory cache too — otherwise, if the permission is
      // re-granted later in the same JS session, the "unchanged" check
      // would skip re-registration while the OS is monitoring nothing.
      registeredRegionIds.clear();
      trace('presence.geofence', 'stopped: no background permission');
    }
    return;
  }

  if (regions.length === 0) {
    const running = await Location.hasStartedGeofencingAsync(PRESENCE_GEOFENCE_TASK).catch(() => false);
    if (running) {
      await Location.stopGeofencingAsync(PRESENCE_GEOFENCE_TASK).catch(() => {});
      registeredRegionIds.clear();
      trace('presence.geofence', 'stopped: no candidate activities');
    }
    return;
  }

  // Skip re-registration when the region set is unchanged. On Android
  // startGeofencingAsync uses INITIAL_TRIGGER_ENTER by default, which
  // fires Enter immediately for any region the user is currently inside —
  // so re-registering the same regions on every AppState foreground (e.g.
  // when the user taps a "Présence détectée" notif) re-fired the Enter
  // event and re-scheduled the local notif on every tap.
  const newIds = new Set(regions.map((r) => String(r.identifier ?? '')));
  const unchanged =
    newIds.size === registeredRegionIds.size &&
    [...newIds].every((id) => registeredRegionIds.has(id));
  if (unchanged) {
    trace('presence.geofence', 'regions unchanged, skip re-register', {
      count: regions.length,
    });
    return;
  }

  try {
    await Location.startGeofencingAsync(PRESENCE_GEOFENCE_TASK, regions);
    registeredRegionIds = newIds;
    trace('presence.geofence', 'registered regions', { count: regions.length });
  } catch (err) {
    // Surface as a Sentry event, not just a breadcrumb. Registration failure
    // means the user gets no auto-confirmation at all when the app is closed —
    // we need to know about it without waiting for an unrelated crash to
    // attach the breadcrumbs to.
    captureWarning('presence.geofence', 'registration failed', {
      reason: err instanceof Error ? err.message : String(err),
      region_count: regions.length,
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
      registeredRegionIds.clear();
      void cleanupDeferredPresenceNotifs(null);
      void stopPresenceForegroundService('hook unmounted');
      trace('presence.geofence', 'stopped: hook unmounted');
    };
  }, [enabled]);
}
