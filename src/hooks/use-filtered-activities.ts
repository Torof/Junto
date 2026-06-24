import { useMemo } from 'react';
import dayjs from 'dayjs';
import { type NearbyActivity } from '@/services/activity-service';
import { useMapStore } from '@/store/map-store';
import { levelSpanMatchesTiers } from '@/constants/sport-levels';
import { distanceMeters } from '@/utils/geo';

export function useFilteredActivities(
  activities: NearbyActivity[],
  userLocation?: [number, number] | null,
): NearbyActivity[] {
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

    // Level tier filter — an activity matches if its level span [level, level_max]
    // overlaps any selected tier (open / unmappable levels soft-fail).
    if (filters.levelTiers.length > 0) {
      filtered = filtered.filter((a) =>
        levelSpanMatchesTiers(a.sport_key, a.level, a.level_max, filters.levelTiers),
      );
    }

    // Visibility filter
    if (filters.visibilities.length > 0) {
      filtered = filtered.filter((a) => {
        if (a.visibility === 'public') return filters.visibilities.includes('public');
        if (a.visibility === 'approval') return filters.visibilities.includes('approval');
        return true; // private_link/private_link_approval: not controlled by this filter
      });
    }

    // Radius filter — distance from userLocation (lng, lat). When the user
    // hasn't shared GPS or hasn't set a radius, no filter applies.
    if (filters.radiusKm !== null && userLocation) {
      const limitMeters = filters.radiusKm * 1000;
      filtered = filtered.filter(
        (a) => distanceMeters(userLocation[1], userLocation[0], a.lat, a.lng) <= limitMeters,
      );
    }

    // Sort. sortBy === null means 'default' (date ascending). When the
    // user picks a chip the 3-state cycle is asc → desc → null (back
    // to default). Direction is honoured only when sortBy is non-null.
    const { sortBy, sortDir } = filters;
    const effectiveSort = sortBy ?? 'date';
    const dir = sortBy !== null && sortDir === 'desc' ? -1 : 1;
    const sorted = [...filtered];
    if (effectiveSort === 'date') {
      sorted.sort((a, b) => (dayjs(a.starts_at).valueOf() - dayjs(b.starts_at).valueOf()) * dir);
    } else if (effectiveSort === 'distance' && userLocation) {
      sorted.sort((a, b) => (
        distanceMeters(userLocation[1], userLocation[0], a.lat, a.lng) -
        distanceMeters(userLocation[1], userLocation[0], b.lat, b.lng)
      ) * dir);
    } else if (effectiveSort === 'sport') {
      sorted.sort((a, b) => a.sport_key.localeCompare(b.sport_key) * dir);
    } else if (effectiveSort === 'remaining') {
      // Open activities (null max) treated as Infinity remaining.
      const remaining = (a: NearbyActivity) =>
        a.max_participants === null ? Infinity : a.max_participants - a.participant_count;
      sorted.sort((a, b) => (remaining(a) - remaining(b)) * dir);
    }

    return sorted;
  }, [activities, filters.sportKeys, filters.dateMode, filters.specificDate, filters.rangeFrom, filters.rangeTo, filters.levelTiers, filters.visibilities, filters.radiusKm, filters.sortBy, filters.sortDir, userLocation]);
}
