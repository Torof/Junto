import { useEffect, useRef, useState } from 'react';
import * as Location from 'expo-location';
import { geolocationService } from '@/services/geolocation-service';

// Default center: Briançon, France
const DEFAULT_CENTER: [number, number] = [6.6323, 44.8967];

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
        if (status === 'granted') {
          const location = await Location.getCurrentPositionAsync({
            accuracy: Location.Accuracy.Balanced,
          });
          if (cancelled) return;
          const initial: [number, number] = [location.coords.longitude, location.coords.latitude];
          setCenter(initial);
          setCurrentLocation(initial);
          setIsLoading(false);

          watcherRef.current = await Location.watchPositionAsync(
            {
              accuracy: Location.Accuracy.Balanced,
              timeInterval: 5000,
              distanceInterval: 10,
            },
            (update) => {
              setCurrentLocation([update.coords.longitude, update.coords.latitude]);
            },
          );
          return;
        }
      } catch {
        // GPS failed — fall through to IP
      }

      const ipCenter = await geolocationService.getInitialCenter();
      if (cancelled) return;
      setCenter(ipCenter);
      setIsLoading(false);
    })();

    return () => {
      cancelled = true;
      watcherRef.current?.remove();
      watcherRef.current = null;
    };
  }, []);

  return { center, currentLocation, isLoading };
}
