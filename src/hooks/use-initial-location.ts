import { useEffect, useRef, useState } from 'react';
import * as Location from 'expo-location';
import { geolocationService } from '@/services/geolocation-service';

// Default center: Briançon, France
const DEFAULT_CENTER: [number, number] = [6.6323, 44.8967];

// Cache freshness gate. Anything older than 60s or coarser than 100m gets
// rejected — those thresholds bypass the "stale cache shown for 17h"
// failure mode (cached fused fix from a different city, never refreshed
// because no foreground request triggered GPS).
const CACHE_MAX_AGE_MS = 60_000;
const CACHE_REQUIRED_ACCURACY_M = 100;

export function useInitialLocation() {
  const [center, setCenter] = useState<[number, number]>(DEFAULT_CENTER);
  const [currentLocation, setCurrentLocation] = useState<[number, number] | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const watcherRef = useRef<Location.LocationSubscription | null>(null);

  useEffect(() => {
    let cancelled = false;

    (async () => {
      try {
        const { status } = await Location.requestForegroundPermissionsAsync();
        if (status !== 'granted') {
          const ipCenter = await geolocationService.getInitialCenter();
          if (cancelled) return;
          setCenter(ipCenter);
          setIsLoading(false);
          return;
        }

        // Fast path: if the OS has a recent enough cached fix, render
        // with it immediately so the user sees the map populated. This
        // is instant — no GPS warmup needed.
        const cached = await Location.getLastKnownPositionAsync({
          maxAge: CACHE_MAX_AGE_MS,
          requiredAccuracy: CACHE_REQUIRED_ACCURACY_M,
        });
        if (cached && !cancelled) {
          const initial: [number, number] = [cached.coords.longitude, cached.coords.latitude];
          setCenter(initial);
          setCurrentLocation(initial);
          setIsLoading(false);
        }

        // Canonical path: force a fresh High-accuracy fix. On Android
        // this maps to PRIORITY_HIGH_ACCURACY which spins up GPS even
        // when fused has a cached value. Takes 3-5s on cold-start;
        // updates the map once the lock comes in.
        const fresh = await Location.getCurrentPositionAsync({
          accuracy: Location.Accuracy.High,
        });
        if (cancelled) return;
        const freshCoords: [number, number] = [
          fresh.coords.longitude,
          fresh.coords.latitude,
        ];
        setCenter(freshCoords);
        setCurrentLocation(freshCoords);
        setIsLoading(false);

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
            setCurrentLocation([update.coords.longitude, update.coords.latitude]);
          },
        );
      } catch {
        const ipCenter = await geolocationService.getInitialCenter();
        if (cancelled) return;
        setCenter(ipCenter);
        setIsLoading(false);
      }
    })();

    return () => {
      cancelled = true;
      watcherRef.current?.remove();
      watcherRef.current = null;
    };
  }, []);

  return { center, currentLocation, isLoading };
}
