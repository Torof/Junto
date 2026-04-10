import { useQuery } from '@tanstack/react-query';
import { activityService } from '@/services/activity-service';

export function useNearbyActivities() {
  return useQuery({
    queryKey: ['activities', 'nearby'],
    queryFn: () => activityService.getNearby(),
  });
}
