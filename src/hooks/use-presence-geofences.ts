import { useEffect } from 'react';
import * as Location from 'expo-location';
import { AppState } from 'react-native';
import { supabase } from '@/services/supabase';
import { PRESENCE_GEOFENCE_TASK } from '@/lib/presence-geofence-task';
import { trace } from '@/lib/sentry';

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

const RADIUS_M = 150;
// iOS hard-caps at 20 regions per app. We pick one location per activity (the
// meeting point if set, otherwise start), then trim to the closest 20 by
// starts_at proximity.
const MAX_REGIONS = 20;
// Reject GPS samples too imprecise to safely auto-confirm. 50m is a balance
// between catching forest/canyon drift and not being so strict we never get
// a usable fix.
const ACCURACY_THRESHOLD_M = 50;

async function buildRegions(): Promise<Location.LocationRegion[]> {
  const { data } = (await supabase.rpc('get_my_active_presence_activities' as 'accept_tos')) as unknown as {
    data: ActiveActivity[] | null;
  };
  const candidates = data ?? [];

  candidates.sort((a, b) => new Date(a.starts_at).getTime() - new Date(b.starts_at).getTime());

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

function distanceMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371000;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// Initial-state check — runs whenever the app comes into focus, regardless of
// background-location permission. The Enter event from the OS only fires on a
// genuine outside→inside transition, so a user who's already on-site at app
// open would never get auto-confirmed. We pull a fresh fix and call the RPC
// directly for any region the user is already inside; server gates on time
// window so calls outside T-15min..T+15min are no-ops.
async function initialStateCheck(regions: Location.LocationRegion[]): Promise<void> {
  if (regions.length === 0) return;

  const fg = await Location.getForegroundPermissionsAsync();
  if (fg.status !== 'granted') {
    trace('presence.geofence', 'initial-state skipped: no foreground permission');
    return;
  }

  let pos: Location.LocationObject;
  try {
    pos = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
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

async function refreshGeofences(): Promise<void> {
  const regions = await buildRegions();

  // Initial-state check needs only foreground permission. Run it before
  // anything else so users with "While Using" still get the on-app-open
  // auto-confirmation when they're already on-site.
  await initialStateCheck(regions);

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
      Location.stopGeofencingAsync(PRESENCE_GEOFENCE_TASK).catch(() => {});
      trace('presence.geofence', 'stopped: hook unmounted');
    };
  }, [enabled]);
}
