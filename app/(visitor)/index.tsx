import { useState, useCallback, useRef } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { JuntoMapView, type MapBounds } from '@/components/map-view';
import { ActivityPopup } from '@/components/activity-popup';
import { ActivitySearch } from '@/components/activity-search';
import { ViewToggle } from '@/components/view-toggle';
import { FilterButton } from '@/components/filter-bar';
import { FilterSheet } from '@/components/filter-sheet';
import { SearchAreaButton } from '@/components/search-area-button';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { useNearbyActivities, type MapBounds as QueryBounds } from '@/hooks/use-nearby-activities';
import { useFilteredActivities } from '@/hooks/use-filtered-activities';
import { useMapStore } from '@/store/map-store';
import { type NearbyActivity } from '@/services/activity-service';

export default function VisitorMapScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { center } = useInitialLocation();
  const [selectedActivity, setSelectedActivity] = useState<NearbyActivity | null>(null);
  const [showFilters, setShowFilters] = useState(false);
  const { viewMode } = useMapStore();

  // Bounds-based fetching
  const [searchBounds, setSearchBounds] = useState<QueryBounds | null>(null);
  const [showSearchButton, setShowSearchButton] = useState(false);
  const lastSearchCenter = useRef<{ lng: number; lat: number } | null>(null);
  const currentBounds = useRef<MapBounds | null>(null);
  const initialSearchDone = useRef(false);

  const { data: activities } = useNearbyActivities(searchBounds);
  const filtered = useFilteredActivities(activities ?? []);

  const doSearch = useCallback((bounds: MapBounds) => {
    lastSearchCenter.current = { lng: bounds.centerLng, lat: bounds.centerLat };
    const lngSpan = bounds.neLng - bounds.swLng;
    const latSpan = bounds.neLat - bounds.swLat;
    setSearchBounds({
      swLng: bounds.swLng - lngSpan * 0.5,
      swLat: bounds.swLat - latSpan * 0.5,
      neLng: bounds.neLng + lngSpan * 0.5,
      neLat: bounds.neLat + latSpan * 0.5,
    });
    setShowSearchButton(false);
  }, []);

  const handleBoundsChange = useCallback((bounds: MapBounds) => {
    currentBounds.current = bounds;

    if (!initialSearchDone.current) {
      initialSearchDone.current = true;
      doSearch(bounds);
      return;
    }

    if (searchBounds && !(bounds.swLng >= searchBounds.swLng && bounds.swLat >= searchBounds.swLat && bounds.neLng <= searchBounds.neLng && bounds.neLat <= searchBounds.neLat)) {
      doSearch(bounds);
      return;
    }

    if (lastSearchCenter.current) {
      const viewportWidth = Math.abs(bounds.neLng - bounds.swLng);
      const dlat = bounds.centerLat - lastSearchCenter.current.lat;
      const dlng = bounds.centerLng - lastSearchCenter.current.lng;
      if (Math.sqrt(dlat * dlat + dlng * dlng) > viewportWidth * 0.3) {
        setShowSearchButton(true);
      }
    }
  }, [searchBounds, doSearch]);

  const handleSearchArea = useCallback(() => {
    if (currentBounds.current) doSearch(currentBounds.current);
  }, [doSearch]);

  return (
    <View style={styles.container}>
      <FilterButton onPress={() => setShowFilters(true)} />
      <ViewToggle />

      {/* Sign in banner */}
      <View style={[styles.banner, { top: insets.top + 48 }]}>
        <Text style={styles.bannerText}>{t('visitor.explore')}</Text>
        <Pressable style={styles.signInButton} onPress={() => router.push('/(visitor)/login')}>
          <Text style={styles.signInText}>{t('auth.signIn')}</Text>
        </Pressable>
      </View>

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
                router.push(`/(visitor)/activity/${selectedActivity.id}`);
                setSelectedActivity(null);
              }}
              onClose={() => setSelectedActivity(null)}
            />
          )}
        </>
      ) : (
        <ActivitySearch activities={activities ?? []} userLocation={center} routePrefix="/(visitor)" />
      )}

      <FilterSheet visible={showFilters} onClose={() => setShowFilters(false)} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  banner: {
    position: 'absolute',
    left: spacing.md,
    right: spacing.md,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: colors.background + 'F0',
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    zIndex: 10,
  },
  bannerText: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    flex: 1,
    marginRight: spacing.md,
  },
  signInButton: {
    backgroundColor: colors.cta,
    borderRadius: radius.full,
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.sm,
  },
  signInText: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: 'bold',
  },
});
