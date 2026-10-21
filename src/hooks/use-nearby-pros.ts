import { useQuery, keepPreviousData } from '@tanstack/react-query';
import { proService } from '@/services/pro-service';
import type { MapBounds } from './use-nearby-activities';

// Sibling of useNearbyActivities — fetches pro pins for the current
// viewport (keep-previous-data). No realtime: pro pages change rarely and
// the viewport refetch keeps them fresh (the table is not published).
export function useNearbyPros(bounds?: MapBounds | null) {
  return useQuery({
    queryKey: ['pros', 'nearby', bounds],
    queryFn: () => proService.getNearby(bounds ?? undefined),
    enabled: !!bounds,
    placeholderData: keepPreviousData,
  });
}
