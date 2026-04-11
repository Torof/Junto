import { useEffect, useState } from 'react';
import * as Location from 'expo-location';
import { geolocationService } from '@/services/geolocation-service';

// Default center: Briançon, France
const DEFAULT_CENTER: [number, number] = [6.6323, 44.8967];

export function useInitialLocation() {
  const [center, setCenter] = useState<[number, number]>(DEFAULT_CENTER);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    (async () => {
      try {
        // Try device GPS first
        const { status } = await Location.requestForegroundPermissionsAsync();
        if (status === 'granted') {
          const location = await Location.getCurrentPositionAsync({
            accuracy: Location.Accuracy.Balanced,
          });
          setCenter([location.coords.longitude, location.coords.latitude]);
          setIsLoading(false);
          return;
        }
      } catch {
        // GPS failed — fall through to IP
      }

      // Fallback: IP geolocation
      const ipCenter = await geolocationService.getInitialCenter();
      setCenter(ipCenter);
      setIsLoading(false);
    })();
  }, []);

  return { center, isLoading };
}
