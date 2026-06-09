import { useMemo } from 'react';
import { type ProOffering } from '@/services/pro-offering-service';
import { useMapStore } from '@/store/map-store';
import { getLevelScale } from '@/constants/sport-levels';
import { distanceMeters } from '@/utils/geo';

const OPEN_LEVEL = 'Tous niveaux';

// Mirrors useFilteredActivities for the catalog half of the map.
// Offerings are atemporal (no starts_at) and always public, so the
// date and visibility filters don't apply. Sport / level / radius
// filters and the distance/sport sorts work the same way as for
// activities. The 'date' and 'remaining' sort options fall through
// to a stable order by created_at descending.
export function useFilteredOfferings(
  offerings: ProOffering[],
  userLocation?: [number, number] | null,
): ProOffering[] {
  const { filters } = useMapStore();

  return useMemo(() => {
    let filtered = offerings;

    // Sport filter (multi-select)
    if (filters.sportKeys.length > 0) {
      filtered = filtered.filter((o) => filters.sportKeys.includes(o.sport_key));
    }

    // Level tier filter — same soft-fail semantics as activities.
    if (filters.levelTiers.length > 0) {
      filtered = filtered.filter((o) => {
        if (!o.level || o.level === OPEN_LEVEL) return true;
        const scale = getLevelScale(o.sport_key);
        const option = scale.find((s) => s.label === o.level);
        if (!option?.description) return true;
        return filters.levelTiers.includes(option.description as typeof filters.levelTiers[number]);
      });
    }

    // Radius filter
    if (filters.radiusKm !== null && userLocation) {
      const limitMeters = filters.radiusKm * 1000;
      filtered = filtered.filter(
        (o) => distanceMeters(userLocation[1], userLocation[0], o.lat, o.lng) <= limitMeters,
      );
    }

    // Sort. 'date' and 'remaining' don't apply to offerings — fall
    // through to created_at descending so freshly published catalog
    // items surface first.
    const { sortBy, sortDir } = filters;
    const dir = sortBy !== null && sortDir === 'desc' ? -1 : 1;
    const sorted = [...filtered];
    if (sortBy === 'distance' && userLocation) {
      sorted.sort((a, b) => (
        distanceMeters(userLocation[1], userLocation[0], a.lat, a.lng) -
        distanceMeters(userLocation[1], userLocation[0], b.lat, b.lng)
      ) * dir);
    } else if (sortBy === 'sport') {
      sorted.sort((a, b) => a.sport_key.localeCompare(b.sport_key) * dir);
    } else {
      // Default + 'date' + 'remaining' all fall here.
      sorted.sort((a, b) => (new Date(b.created_at).getTime() - new Date(a.created_at).getTime()));
    }

    return sorted;
  }, [offerings, filters.sportKeys, filters.levelTiers, filters.radiusKm, filters.sortBy, filters.sortDir, userLocation]);
}
