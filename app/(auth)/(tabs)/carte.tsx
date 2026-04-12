import { useState, useCallback, useRef } from 'react';
import { View, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { SafeAreaView } from 'react-native-safe-area-context';
import { JuntoMapView, type MapBounds } from '@/components/map-view';
import { ActivityPopup } from '@/components/activity-popup';
import { ActivityList } from '@/components/activity-list';
import { ViewToggle } from '@/components/view-toggle';
import { FilterButton } from '@/components/filter-bar';
import { FilterSheet } from '@/components/filter-sheet';
import { CreateButton } from '@/components/create-button';
import { SearchAreaButton } from '@/components/search-area-button';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { useNearbyActivities, type MapBounds as QueryBounds } from '@/hooks/use-nearby-activities';
import { useFilteredActivities } from '@/hooks/use-filtered-activities';
import { useMapStore } from '@/store/map-store';
import { type NearbyActivity } from '@/services/activity-service';
import { colors } from '@/constants/theme';

const BUFFER = 0.5; // 50% buffer around viewport

function addBuffer(bounds: MapBounds): QueryBounds {
  const lngSpan = bounds.neLng - bounds.swLng;
  const latSpan = bounds.neLat - bounds.swLat;
  return {
    swLng: bounds.swLng - lngSpan * BUFFER,
    swLat: bounds.swLat - latSpan * BUFFER,
    neLng: bounds.neLng + lngSpan * BUFFER,
    neLat: bounds.neLat + latSpan * BUFFER,
  };
}

function isWithinFetchedBounds(current: MapBounds, fetched: QueryBounds): boolean {
  return (
    current.swLng >= fetched.swLng &&
    current.swLat >= fetched.swLat &&
    current.neLng <= fetched.neLng &&
    current.neLat <= fetched.neLat
  );
}

function panDistance(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const dlat = lat2 - lat1;
  const dlng = lng2 - lng1;
  return Math.sqrt(dlat * dlat + dlng * dlng);
}

export default function CarteScreen() {
  const router = useRouter();
  const { center } = useInitialLocation();
  const { viewMode } = useMapStore();
  const [selectedActivity, setSelectedActivity] = useState<NearbyActivity | null>(null);
  const [showFilters, setShowFilters] = useState(false);

  const [searchBounds, setSearchBounds] = useState<QueryBounds | null>(null);
  const [showSearchButton, setShowSearchButton] = useState(false);
  const lastSearchCenter = useRef<{ lng: number; lat: number } | null>(null);
  const currentBounds = useRef<MapBounds | null>(null);
  const initialSearchDone = useRef(false);

  const { data: activities } = useNearbyActivities(searchBounds);
  const filtered = useFilteredActivities(activities ?? []);

  const doSearch = useCallback((bounds: MapBounds) => {
    lastSearchCenter.current = { lng: bounds.centerLng, lat: bounds.centerLat };
    setSearchBounds(addBuffer(bounds));
    setShowSearchButton(false);
  }, []);

  const handleBoundsChange = useCallback((bounds: MapBounds) => {
    currentBounds.current = bounds;

    // First load — auto-search
    if (!initialSearchDone.current) {
      initialSearchDone.current = true;
      doSearch(bounds);
      return;
    }

    // If viewport extends beyond fetched bounds (zoom out) — auto-refetch silently
    if (searchBounds && !isWithinFetchedBounds(bounds, searchBounds)) {
      doSearch(bounds);
      return;
    }

    // If user panned significantly — show search button (don't auto-fetch)
    if (lastSearchCenter.current) {
      const viewportWidth = Math.abs(bounds.neLng - bounds.swLng);
      const dist = panDistance(
        lastSearchCenter.current.lat, lastSearchCenter.current.lng,
        bounds.centerLat, bounds.centerLng,
      );
      if (dist > viewportWidth * 0.3) {
        setShowSearchButton(true);
      }
    }
  }, [searchBounds, doSearch]);

  const handleSearchArea = useCallback(() => {
    if (currentBounds.current) {
      doSearch(currentBounds.current);
    }
  }, [doSearch]);

  return (
    <View style={styles.container}>
      <SafeAreaView edges={['top']} style={styles.statusBar} />

      <View style={styles.content}>
        <CreateButton />
        <FilterButton onPress={() => setShowFilters(true)} />
        <ViewToggle />

        {viewMode === 'map' ? (
          <>
            {showSearchButton && <SearchAreaButton onPress={handleSearchArea} />}

            <JuntoMapView
              center={center}
              activities={filtered}
              onActivityPress={setSelectedActivity}
              onBoundsChange={handleBoundsChange}
            />

            {selectedActivity && (
              <ActivityPopup
                activity={selectedActivity}
                onViewDetail={() => {
                  router.push(`/(auth)/activity/${selectedActivity.id}`);
                  setSelectedActivity(null);
                }}
                onClose={() => setSelectedActivity(null)}
              />
            )}
          </>
        ) : (
          <ActivityList activities={filtered} routePrefix="/(auth)" />
        )}

        <FilterSheet visible={showFilters} onClose={() => setShowFilters(false)} />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  statusBar: {
    backgroundColor: colors.background,
  },
  content: {
    flex: 1,
  },
});
