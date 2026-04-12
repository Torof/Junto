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

function getDistance(lat1: number, lng1: number, lat2: number, lng2: number): number {
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

  // Bounds-based fetching
  const [searchBounds, setSearchBounds] = useState<QueryBounds | null>(null);
  const [showSearchButton, setShowSearchButton] = useState(false);
  const lastSearchCenter = useRef<{ lng: number; lat: number } | null>(null);
  const initialSearchDone = useRef(false);

  const { data: activities } = useNearbyActivities(searchBounds);
  const filtered = useFilteredActivities(activities ?? []);

  const handleBoundsChange = useCallback((bounds: MapBounds) => {
    // First load — auto-search
    if (!initialSearchDone.current) {
      initialSearchDone.current = true;
      lastSearchCenter.current = { lng: bounds.centerLng, lat: bounds.centerLat };
      setSearchBounds({
        swLng: bounds.swLng,
        swLat: bounds.swLat,
        neLng: bounds.neLng,
        neLat: bounds.neLat,
      });
      return;
    }

    // Check if user moved significantly from last search
    if (lastSearchCenter.current) {
      const viewportWidth = Math.abs(bounds.neLng - bounds.swLng);
      const dist = getDistance(
        lastSearchCenter.current.lat, lastSearchCenter.current.lng,
        bounds.centerLat, bounds.centerLng,
      );
      if (dist > viewportWidth * 0.3) {
        setShowSearchButton(true);
      }
    }
  }, []);

  const handleSearch = useCallback(() => {
    if (!lastSearchCenter.current) return;
    // We need current bounds — we'll get them from the next camera change
    // For now, trigger a re-search with wider bounds around last known position
    setShowSearchButton(false);
  }, []);

  // Better approach: store current bounds and use them on search
  const currentBounds = useRef<MapBounds | null>(null);

  const handleBoundsChangeWithRef = useCallback((bounds: MapBounds) => {
    currentBounds.current = bounds;
    handleBoundsChange(bounds);
  }, [handleBoundsChange]);

  const handleSearchArea = useCallback(() => {
    const b = currentBounds.current;
    if (!b) return;
    lastSearchCenter.current = { lng: b.centerLng, lat: b.centerLat };
    setSearchBounds({
      swLng: b.swLng,
      swLat: b.swLat,
      neLng: b.neLng,
      neLat: b.neLat,
    });
    setShowSearchButton(false);
  }, []);

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
              onBoundsChange={handleBoundsChangeWithRef}
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
