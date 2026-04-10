import { View, StyleSheet } from 'react-native';
import { JuntoMapView, type ActivityPin } from '@/components/map-view';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { useNearbyActivities } from '@/hooks/use-nearby-activities';

export default function CarteScreen() {
  const { center } = useInitialLocation();
  const { data: activities } = useNearbyActivities();

  const pins: ActivityPin[] = (activities ?? [])
    .filter((a) => a.lng != null && a.lat != null)
    .map((a) => ({
      id: a.id,
      title: a.title,
      coordinate: [a.lng, a.lat] as [number, number],
    }));

  return (
    <View style={styles.container}>
      <JuntoMapView center={center} pins={pins} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
});
