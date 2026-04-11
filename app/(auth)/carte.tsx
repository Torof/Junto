import { useState } from 'react';
import { View, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { JuntoMapView } from '@/components/map-view';
import { ActivityPopup } from '@/components/activity-popup';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { useNearbyActivities } from '@/hooks/use-nearby-activities';
import { type NearbyActivity } from '@/services/activity-service';

export default function CarteScreen() {
  const router = useRouter();
  const { center } = useInitialLocation();
  const { data: activities } = useNearbyActivities();
  const [selectedActivity, setSelectedActivity] = useState<NearbyActivity | null>(null);

  return (
    <View style={styles.container}>
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
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
});
