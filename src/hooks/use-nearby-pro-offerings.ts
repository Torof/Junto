import { useQuery, keepPreviousData } from '@tanstack/react-query';
import { proOfferingService } from '@/services/pro-offering-service';
import type { MapBounds } from './use-nearby-activities';

// Sibling of useNearbyActivities + useNearbyPros — fetches pro offering
// card pins for the current viewport (keep-previous-data). No realtime: the
// viewport refetch keeps them fresh (the table is not published).
export function useNearbyProOfferings(bounds?: MapBounds | null) {
  return useQuery({
    queryKey: ['pro-offerings', 'nearby', bounds],
    queryFn: () => proOfferingService.getNearby(bounds ?? undefined),
    enabled: !!bounds,
    placeholderData: keepPreviousData,
  });
}
