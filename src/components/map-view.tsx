import { Pressable, StyleSheet } from 'react-native';
import Mapbox from '@rnmapbox/maps';
import { type NearbyActivity } from '@/services/activity-service';
import { ActivityPin } from './activity-pin';

const MAPBOX_TOKEN = process.env.EXPO_PUBLIC_MAPBOX_ACCESS_TOKEN;

if (!MAPBOX_TOKEN) {
  throw new Error('Missing EXPO_PUBLIC_MAPBOX_ACCESS_TOKEN in .env');
}

Mapbox.setAccessToken(MAPBOX_TOKEN);
Mapbox.setTelemetryEnabled(false);

const OUTDOORS_STYLE = 'mapbox://styles/mapbox/outdoors-v12';
const DEFAULT_CENTER: [number, number] = [6.6323, 44.8967];
const DEFAULT_ZOOM = 10;

interface MapViewProps {
  center?: [number, number];
  zoom?: number;
  activities?: NearbyActivity[];
  onActivityPress?: (activity: NearbyActivity) => void;
  onMapPress?: (lng: number, lat: number) => void;
}

export function JuntoMapView({
  center = DEFAULT_CENTER,
  zoom = DEFAULT_ZOOM,
  activities = [],
  onActivityPress,
  onMapPress,
}: MapViewProps) {
  return (
    <Mapbox.MapView
      style={styles.map}
      styleURL={OUTDOORS_STYLE}
      logoEnabled={false}
      attributionEnabled={false}
      compassEnabled
      scaleBarEnabled={false}
      onPress={(feature) => {
        if (onMapPress && feature.geometry.type === 'Point') {
          const [lng, lat] = feature.geometry.coordinates;
          if (typeof lng === 'number' && typeof lat === 'number') {
            onMapPress(lng, lat);
          }
        }
      }}
    >
      <Mapbox.Camera
        defaultSettings={{
          centerCoordinate: center,
          zoomLevel: zoom,
        }}
      />

      {activities.map((activity) => (
        <Mapbox.MarkerView
          key={activity.id}
          id={activity.id}
          coordinate={[activity.lng, activity.lat]}
        >
          <Pressable onPress={() => onActivityPress?.(activity)}>
            <ActivityPin activity={activity} />
          </Pressable>
        </Mapbox.MarkerView>
      ))}
    </Mapbox.MapView>
  );
}

const styles = StyleSheet.create({
  map: {
    flex: 1,
  },
});
