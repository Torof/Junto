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
    if (filters.dateMode === 'today') {
      filtered = filtered.filter((a) => dayjs(a.starts_at).isSame(dayjs(), 'day'));
    } else if (filters.dateMode === 'week') {
      const weekFromNow = dayjs().add(7, 'day');
      filtered = filtered.filter((a) => dayjs(a.starts_at).isBefore(weekFromNow));
    } else if (filters.dateMode === 'date' && filters.specificDate) {
      filtered = filtered.filter((a) => dayjs(a.starts_at).isSame(dayjs(filters.specificDate), 'day'));
    } else if (filters.dateMode === 'range' && filters.rangeFrom && filters.rangeTo) {
      const from = dayjs(filters.rangeFrom).startOf('day');
      const to = dayjs(filters.rangeTo).endOf('day');
      filtered = filtered.filter((a) => {
        const d = dayjs(a.starts_at);
        return d.isAfter(from) && d.isBefore(to);
      });
    }

    return filtered;
  }, [activities, filters.sportKeys, filters.dateMode, filters.specificDate, filters.rangeFrom, filters.rangeTo]);
}
