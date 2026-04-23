import { useMemo } from 'react';
import dayjs from 'dayjs';
import { type NearbyActivity } from '@/services/activity-service';
import { useMapStore } from '@/store/map-store';
import { getLevelScale } from '@/constants/sport-levels';

const OPEN_LEVEL = 'Tous niveaux';

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

    // Level tier filter (soft-fail: activities whose level can't be mapped to any
    // scale option pass through — prevents accidentally hiding activities with
    // free-form or missing level data)
    if (filters.levelTiers.length > 0) {
      filtered = filtered.filter((a) => {
        if (!a.level || a.level === OPEN_LEVEL) return true;
        const scale = getLevelScale(a.sport_key);
        const option = scale.find((o) => o.label === a.level);
        if (!option?.description) return true; // soft-fail
        return filters.levelTiers.includes(option.description as typeof filters.levelTiers[number]);
      });
    }

    // Visibility filter
    if (filters.visibilities.length > 0) {
      filtered = filtered.filter((a) => {
        if (a.visibility === 'public') return filters.visibilities.includes('public');
        if (a.visibility === 'approval') return filters.visibilities.includes('approval');
        return true; // private_link/private_link_approval: not controlled by this filter
      });
    }

    return filtered;
  }, [activities, filters.sportKeys, filters.dateMode, filters.specificDate, filters.rangeFrom, filters.rangeTo, filters.levelTiers, filters.visibilities]);
}
