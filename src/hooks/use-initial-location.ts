import { useEffect, useRef, useState } from 'react';
import * as Location from 'expo-location';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { geolocationService } from '@/services/geolocation-service';
import { usePermissionPromptStore } from '@/store/permission-prompt-store';

// Where the map opens (Scott 2026-10-26: « sur la région où on est, tout de
// suite — jamais la France entière »). Sources, best first; a weaker one
// never overrides a stronger one that already landed:
//   4  fresh GPS fix                      → local view (GPS_ZOOM)
//   3  last fix known to the OS, any age  → the region (REGION_ZOOM)
//   2  last fix this app stored           → the region, instant, offline
//   1  IP address                         → the area (REGION_ZOOM)
//   0  nothing yet                        → France
const FRANCE_CENTER: [number, number] = [2.35, 46.6];
const FRANCE_ZOOM = 5;
const GPS_ZOOM = 10;
const REGION_ZOOM = 9;
const LAST_FIX_KEY = 'junto.lastFix';

// Cache freshness gate for the LIVE position dot only. Anything older than
// 60s or coarser than 100m is not shown as « me » — that threshold bypasses
// the "stale cache shown for 17h" failure mode (cached fused fix from a
// different city, never refreshed). The camera is less picky: a fix from
// another city still opens the right region, and the fresh fix corrects it.
const CACHE_MAX_AGE_MS = 60_000;
const CACHE_REQUIRED_ACCURACY_M = 100;

type Fix = [number, number];

async function readStoredFix(): Promise<Fix | null> {
  try {
    const raw = await AsyncStorage.getItem(LAST_FIX_KEY);
    if (!raw) return null;
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed) || parsed.length !== 2) return null;
    const [lng, lat] = parsed as [unknown, unknown];
    if (typeof lng !== 'number' || typeof lat !== 'number' || !Number.isFinite(lng) || !Number.isFinite(lat)) return null;
    return [lng, lat];
  } catch {
    return null;
  }
}

function storeFix(fix: Fix) {
  AsyncStorage.setItem(LAST_FIX_KEY, JSON.stringify(fix)).catch(() => {});
}

// Never ASKS for the permission (Scott 2026-10-24): it only checks. Without
// it the map opens on the last stored fix or the IP area; the moment
// lib/permissions.ts gets it (« me localiser », « Autour de moi »…), every
// mounted copy starts locating.
export function useInitialLocation() {
  const locationGranted = usePermissionPromptStore((s) => s.locationGranted);
  const [center, setCenter] = useState<Fix>(FRANCE_CENTER);
  const [zoom, setZoom] = useState(FRANCE_ZOOM);
  const [currentLocation, setCurrentLocation] = useState<Fix | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const watcherRef = useRef<Location.LocationSubscription | null>(null);
  const rankRef = useRef(0);

  useEffect(() => {
    let cancelled = false;

    // Apply a candidate centre only if nothing stronger has landed.
    const apply = (fix: Fix, rank: number, z: number) => {
      if (cancelled || rank < rankRef.current) return;
      rankRef.current = rank;
      setCenter(fix);
      setZoom(z);
      setIsLoading(false);
    };

    const applyIpCenter = async () => {
      if (rankRef.current >= 2) { setIsLoading(false); return; } // a stored fix beats the IP
      const ipCenter = await geolocationService.getIpCenter();
      if (cancelled) return;
      if (ipCenter) apply(ipCenter, 1, REGION_ZOOM);
      setIsLoading(false);
    };

    (async () => {
      // Instant, offline: where the app last saw the user.
      const stored = await readStoredFix();
      if (stored) apply(stored, 2, REGION_ZOOM);

      try {
        const { status } = await Location.getForegroundPermissionsAsync();
        if (status !== 'granted') {
          await applyIpCenter();
          return;
        }
        usePermissionPromptStore.getState().setLocationGranted(true);

        // The OS's last fix, whatever its age: enough for the region, no
        // GPS warm-up. Fresh and accurate enough → also the live dot.
        const lastKnown = await Location.getLastKnownPositionAsync();
        if (lastKnown && !cancelled) {
          const fix: Fix = [lastKnown.coords.longitude, lastKnown.coords.latitude];
          apply(fix, 3, REGION_ZOOM);
          const ageOk = Date.now() - lastKnown.timestamp <= CACHE_MAX_AGE_MS;
          const accOk = lastKnown.coords.accuracy != null && lastKnown.coords.accuracy <= CACHE_REQUIRED_ACCURACY_M;
          if (ageOk && accOk) {
            setCurrentLocation(fix);
            apply(fix, 4, GPS_ZOOM);
          }
        } else if (rankRef.current < 2) {
          // No fix anywhere on the device: the IP, while the GPS warms up.
          void applyIpCenter();
        }

        // Canonical path: force a fresh High-accuracy fix. On Android
        // this maps to PRIORITY_HIGH_ACCURACY which spins up GPS even
        // when fused has a cached value. Takes 3-5s on cold-start;
        // updates the map once the lock comes in.
        const fresh = await Location.getCurrentPositionAsync({
          accuracy: Location.Accuracy.High,
        });
        if (cancelled) return;
        const freshCoords: Fix = [fresh.coords.longitude, fresh.coords.latitude];
        apply(freshCoords, 4, GPS_ZOOM);
        setCurrentLocation(freshCoords);
        storeFix(freshCoords);

        // Watcher streams High-accuracy updates so the live position
        // marker tracks the user as they move. Same accuracy as the
        // initial fresh fix so it doesn't fall back to fused cache.
        watcherRef.current = await Location.watchPositionAsync(
          {
            accuracy: Location.Accuracy.High,
            timeInterval: 5000,
            distanceInterval: 10,
          },
          (update) => {
            const fix: Fix = [update.coords.longitude, update.coords.latitude];
            setCurrentLocation(fix);
            storeFix(fix);
          },
        );
      } catch {
        await applyIpCenter();
      }
    })();

    return () => {
      cancelled = true;
      watcherRef.current?.remove();
      watcherRef.current = null;
    };
  }, [locationGranted]);

  return { center, zoom, currentLocation, isLoading };
}
