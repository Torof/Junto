import { useMemo } from 'react';
import dayjs from 'dayjs';
import { type NearbyActivity } from '@/services/activity-service';
import { useMapStore } from '@/store/map-store';

export function useFilteredActivities(activities: NearbyActivity[]): NearbyActivity[] {
  const { filters } = useMapStore();

  return useMemo(() => {
    let filtered = activities;

    // Sport filter (multi-select)
    if (filters.sportKeys.length > 0) {
      filtered = filtered.filter((a) => filters.sportKeys.includes(a.sport_key));
    }

    // Date filter
    if (filters.dateRange === 'today') {
      filtered = filtered.filter((a) => dayjs(a.starts_at).isSame(dayjs(), 'day'));
    } else if (filters.dateRange === 'week') {
      const weekFromNow = dayjs().add(7, 'day');
      filtered = filtered.filter((a) => dayjs(a.starts_at).isBefore(weekFromNow));
    }

    return filtered;
  }, [activities, filters.sportKeys, filters.dateRange]);
}
