import { StyleSheet } from 'react-native';
import Mapbox from '@rnmapbox/maps';
const MAPBOX_TOKEN = process.env.EXPO_PUBLIC_MAPBOX_ACCESS_TOKEN;

if (!MAPBOX_TOKEN) {
  throw new Error('Missing EXPO_PUBLIC_MAPBOX_ACCESS_TOKEN in .env');
}

Mapbox.setAccessToken(MAPBOX_TOKEN);
Mapbox.setTelemetryEnabled(false);

const OUTDOORS_STYLE = 'mapbox://styles/mapbox/outdoors-v12';
const DEFAULT_CENTER: [number, number] = [6.6323, 44.8967];
const DEFAULT_ZOOM = 10;

export interface ActivityPin {
  id: string;
  title: string;
  coordinate: [number, number];
}

interface MapViewProps {
  center?: [number, number];
  zoom?: number;
  pins?: ActivityPin[];
}

export function JuntoMapView({ center = DEFAULT_CENTER, zoom = DEFAULT_ZOOM, pins = [] }: MapViewProps) {
  return (
    <Mapbox.MapView
      style={styles.map}
      styleURL={OUTDOORS_STYLE}
      logoEnabled={false}
      attributionEnabled={false}
      compassEnabled
      scaleBarEnabled={false}
    >
      <Mapbox.Camera
        defaultSettings={{
          centerCoordinate: center,
          zoomLevel: zoom,
        }}
      />

      {pins.map((pin) => (
        <Mapbox.PointAnnotation
          key={pin.id}
          id={pin.id}
          coordinate={pin.coordinate}
          title={pin.title}
        >
          <Mapbox.Callout title={pin.title} />
        </Mapbox.PointAnnotation>
      ))}
    </Mapbox.MapView>
  );
}

const styles = StyleSheet.create({
  map: {
    flex: 1,
  },
});
