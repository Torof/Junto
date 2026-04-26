import { useQuery, keepPreviousData } from '@tanstack/react-query';
import { activityService } from '@/services/activity-service';

export interface MapBounds {
  swLng: number;
  swLat: number;
  neLng: number;
  neLat: number;
}

export function useNearbyActivities(bounds?: MapBounds | null) {
  return useQuery({
    queryKey: ['activities', 'nearby', bounds],
    queryFn: () => activityService.getNearby(bounds ?? undefined),
    enabled: !!bounds,
    // Keep the previous result visible while a new viewport fetch is in flight,
    // otherwise pins blink off every time the user pans or zooms.
    placeholderData: keepPreviousData,
  });
}
