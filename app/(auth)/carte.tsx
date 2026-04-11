import { useState } from 'react';
import { View, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { JuntoMapView } from '@/components/map-view';
import { ActivityPopup } from '@/components/activity-popup';
import { ActivityList } from '@/components/activity-list';
import { ViewToggle } from '@/components/view-toggle';
import { FilterButton } from '@/components/filter-bar';
import { FilterSheet } from '@/components/filter-sheet';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { useNearbyActivities } from '@/hooks/use-nearby-activities';
import { useFilteredActivities } from '@/hooks/use-filtered-activities';
import { useMapStore } from '@/store/map-store';
import { type NearbyActivity } from '@/services/activity-service';

export default function CarteScreen() {
  const router = useRouter();
  const { center } = useInitialLocation();
  const { data: activities } = useNearbyActivities();
  const filtered = useFilteredActivities(activities ?? []);
  const { viewMode } = useMapStore();
  const [selectedActivity, setSelectedActivity] = useState<NearbyActivity | null>(null);
  const [showFilters, setShowFilters] = useState(false);

  return (
    <View style={styles.container}>
      <FilterButton onPress={() => setShowFilters(true)} />
      <ViewToggle />

      {viewMode === 'map' ? (
        <>
          <JuntoMapView
            center={center}
            activities={filtered}
            onActivityPress={setSelectedActivity}
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
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
});
