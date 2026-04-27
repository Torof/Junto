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

  // startGeofencingAsync replaces any prior region set for this task.
  try {
    await Location.startGeofencingAsync(PRESENCE_GEOFENCE_TASK, regions);
  } catch {
    // Fail silently — manual paths still work.
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
