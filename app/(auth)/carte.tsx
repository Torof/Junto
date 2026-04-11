import { useState } from 'react';
import { View, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { JuntoMapView } from '@/components/map-view';
import { ActivityPopup } from '@/components/activity-popup';
import { ActivityList } from '@/components/activity-list';
import { ViewToggle } from '@/components/view-toggle';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { useNearbyActivities } from '@/hooks/use-nearby-activities';
import { useMapStore } from '@/store/map-store';
import { type NearbyActivity } from '@/services/activity-service';

export default function CarteScreen() {
  const router = useRouter();
  const { center } = useInitialLocation();
  const { data: activities } = useNearbyActivities();
  const { viewMode } = useMapStore();
  const [selectedActivity, setSelectedActivity] = useState<NearbyActivity | null>(null);

  return (
    <View style={styles.container}>
      <ViewToggle />

      {viewMode === 'map' ? (
        <>
          <JuntoMapView
            center={center}
            activities={activities ?? []}
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
        <ActivityList activities={activities ?? []} routePrefix="/(auth)" />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
});
