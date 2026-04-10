import { View, StyleSheet } from 'react-native';
import { JuntoMapView, type ActivityPin } from '@/components/map-view';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { useNearbyActivities } from '@/hooks/use-nearby-activities';
import { parsePoint } from '@/utils/geo';

export default function CarteScreen() {
  const { center } = useInitialLocation();
  const { data: activities } = useNearbyActivities();

  const pins: ActivityPin[] = (activities ?? [])
    .map((a) => {
      const coord = parsePoint(a.location_start);
      if (!coord) return null;
      return { id: a.id, title: a.title, coordinate: coord };
    })
    .filter((p): p is ActivityPin => p !== null);

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
