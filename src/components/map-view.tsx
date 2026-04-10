import { StyleSheet } from 'react-native';
import Mapbox from '@rnmapbox/maps';

const MAPBOX_TOKEN = process.env.EXPO_PUBLIC_MAPBOX_ACCESS_TOKEN;

if (!MAPBOX_TOKEN) {
  throw new Error('Missing EXPO_PUBLIC_MAPBOX_ACCESS_TOKEN in .env');
}

Mapbox.setAccessToken(MAPBOX_TOKEN);
// Disable telemetry per SECURITY.md — privacy compliance
Mapbox.setTelemetryEnabled(false);

const OUTDOORS_STYLE = 'mapbox://styles/mapbox/outdoors-v12';

// Default center: Briançon, France (founding use case)
const DEFAULT_CENTER: [number, number] = [6.6323, 44.8967];
const DEFAULT_ZOOM = 10;

interface MapViewProps {
  center?: [number, number];
  zoom?: number;
}

export function JuntoMapView({ center = DEFAULT_CENTER, zoom = DEFAULT_ZOOM }: MapViewProps) {
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
    </Mapbox.MapView>
  );
}

const styles = StyleSheet.create({
  map: {
    flex: 1,
  },
});
