import { useEffect } from 'react';
import * as Location from 'expo-location';
import { AppState } from 'react-native';
import { supabase } from '@/services/supabase';
import { PRESENCE_GEOFENCE_TASK } from '@/lib/presence-geofence-task';

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

async function buildRegions(): Promise<Location.LocationRegion[]> {
  const { data } = (await supabase.rpc('get_my_active_presence_activities' as 'accept_tos')) as unknown as {
    data: ActiveActivity[] | null;
  };
  const candidates = data ?? [];

  // Sort by upcoming first (closest start time leading)
  candidates.sort((a, b) => new Date(a.starts_at).getTime() - new Date(b.starts_at).getTime());

  const regions: Location.LocationRegion[] = [];
  for (const a of candidates) {
    if (regions.length >= MAX_REGIONS) break;
    // Prefer the meeting point — that's where people physically gather.
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

async function refreshGeofences() {
  const { status } = await Location.getBackgroundPermissionsAsync();
  if (status !== 'granted') {
    // Without "Always" permission, we can't run background geofencing.
    // Stop any prior task to avoid stale registrations.
    const running = await Location.hasStartedGeofencingAsync(PRESENCE_GEOFENCE_TASK).catch(() => false);
    if (running) {
      await Location.stopGeofencingAsync(PRESENCE_GEOFENCE_TASK).catch(() => {});
    }
    return;
  }

  const regions = await buildRegions();
  if (regions.length === 0) {
    const running = await Location.hasStartedGeofencingAsync(PRESENCE_GEOFENCE_TASK).catch(() => false);
    if (running) {
      await Location.stopGeofencingAsync(PRESENCE_GEOFENCE_TASK).catch(() => {});
    }
    return;
  }

  try {
    await Location.startGeofencingAsync(PRESENCE_GEOFENCE_TASK, regions);
  } catch {
    return;
  }

  // Initial-state check: Android (and sometimes iOS) won't fire ENTER for a
  // region the user is already inside at registration time. Pull a fresh
  // position once and manually validate any matching region — server gates
  // on T-15min so early calls are no-ops.
  try {
    const pos = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
    for (const region of regions) {
      const d = distanceMeters(pos.coords.latitude, pos.coords.longitude, region.latitude, region.longitude);
      if (d <= region.radius) {
        const activityId = String(region.identifier ?? '').split(':')[1];
        if (!activityId) continue;
        try {
          await supabase.rpc('confirm_presence_via_geo' as 'join_activity', {
            p_activity_id: activityId,
            p_lng: pos.coords.longitude,
            p_lat: pos.coords.latitude,
          } as unknown as { p_activity_id: string });
        } catch { /* server gates anyway */ }
      }
    }
  } catch {
    // Best-effort — geofencing's own ENTER will catch later transitions.
  }
}

/**
 * Background geofencing. Registers regions for each upcoming presence-required
 * activity the user has joined; the OS wakes the app on entry and runs the
 * registered TaskManager task, which calls confirm_presence_via_geo.
 *
 * Active only when the user has granted "Always" location permission. Refreshes
 * on app foreground so changes (joins, leaves, new windows opening) are picked
 * up without user action.
 */
export function usePresenceGeofences(enabled: boolean) {
  useEffect(() => {
    if (!enabled) return;
    refreshGeofences();
    const sub = AppState.addEventListener('change', (next) => {
      if (next === 'active') refreshGeofences();
    });
    return () => sub.remove();
  }, [enabled]);
}
