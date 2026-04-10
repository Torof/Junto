import { useEffect, useState } from 'react';
import { geolocationService } from '@/services/geolocation-service';

// Default center: Briançon, France
const DEFAULT_CENTER: [number, number] = [6.6323, 44.8967];

export function useInitialLocation() {
  const [center, setCenter] = useState<[number, number]>(DEFAULT_CENTER);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    geolocationService.getInitialCenter().then((coords) => {
      setCenter(coords);
      setIsLoading(false);
    });
  }, []);

  return { center, isLoading };
}
