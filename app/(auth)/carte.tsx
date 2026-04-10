import { View, StyleSheet } from 'react-native';
import { JuntoMapView } from '@/components/map-view';

export default function CarteScreen() {
  return (
    <View style={styles.container}>
      <JuntoMapView />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
});
