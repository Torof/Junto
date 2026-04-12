import { useState, useMemo, useCallback, useRef } from 'react';
import { Pressable, StyleSheet } from 'react-native';
import Mapbox from '@rnmapbox/maps';
import Supercluster from 'supercluster';
import { type NearbyActivity } from '@/services/activity-service';
import { ActivityPin } from './activity-pin';
import { ClusterPin } from './cluster-pin';

const MAPBOX_TOKEN = process.env.EXPO_PUBLIC_MAPBOX_ACCESS_TOKEN;

if (!MAPBOX_TOKEN) {
  throw new Error('Missing EXPO_PUBLIC_MAPBOX_ACCESS_TOKEN in .env');
}

Mapbox.setAccessToken(MAPBOX_TOKEN);
Mapbox.setTelemetryEnabled(false);

const OUTDOORS_STYLE = 'mapbox://styles/mapbox/outdoors-v12';
const DEFAULT_CENTER: [number, number] = [6.6323, 44.8967];
const DEFAULT_ZOOM = 10;

export interface MapBounds {
  swLng: number;
  swLat: number;
  neLng: number;
  neLat: number;
  centerLng: number;
  centerLat: number;
}

interface MapViewProps {
  center?: [number, number];
  zoom?: number;
  activities?: NearbyActivity[];
  onActivityPress?: (activity: NearbyActivity) => void;
  onMapPress?: (lng: number, lat: number) => void;
  onBoundsChange?: (bounds: MapBounds) => void;
}

type ActivityPoint = Supercluster.PointFeature<{ id: string }>;

export function JuntoMapView({
  center = DEFAULT_CENTER,
  zoom = DEFAULT_ZOOM,
  activities = [],
  onActivityPress,
  onMapPress,
  onBoundsChange,
}: MapViewProps) {
  const [currentZoom, setCurrentZoom] = useState(zoom);
  const [bounds, setBounds] = useState<[number, number, number, number]>([-180, -90, 180, 90]);
  const cameraRef = useRef<Mapbox.Camera>(null);

  const activityMap = useMemo(
    () => new Map(activities.map((a) => [a.id, a])),
    [activities],
  );

  const cluster = useMemo(() => {
    const sc = new Supercluster<{ id: string }>({
      radius: 60,
      maxZoom: 16,
    });
    const points: ActivityPoint[] = activities.map((a) => ({
      type: 'Feature',
      geometry: { type: 'Point', coordinates: [a.lng, a.lat] },
      properties: { id: a.id },
    }));
    sc.load(points);
    return sc;
  }, [activities]);

  const clusters = useMemo(
    () => cluster.getClusters(bounds, Math.floor(currentZoom)),
    [cluster, bounds, currentZoom],
  );

  const handleCameraChanged = useCallback((state: Mapbox.MapState) => {
    setCurrentZoom(state.properties.zoom);
    const sw = state.properties.bounds.sw;
    const ne = state.properties.bounds.ne;
    const swLng = sw[0] ?? -180;
    const swLat = sw[1] ?? -90;
    const neLng = ne[0] ?? 180;
    const neLat = ne[1] ?? 90;
    setBounds([swLng, swLat, neLng, neLat]);
    const center = state.properties.center;
    onBoundsChange?.({
      swLng, swLat, neLng, neLat,
      centerLng: center[0] ?? 0,
      centerLat: center[1] ?? 0,
    });
  }, [onBoundsChange]);

  return (
    <Mapbox.MapView
      style={styles.map}
      styleURL={OUTDOORS_STYLE}
      logoEnabled={false}
      attributionEnabled={false}
      compassEnabled
      scaleBarEnabled={false}
      onCameraChanged={handleCameraChanged}
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
        ref={cameraRef}
        defaultSettings={{
          centerCoordinate: center,
          zoomLevel: zoom,
        }}
      />

      {clusters.map((feature) => {
        const lng = feature.geometry.coordinates[0] ?? 0;
        const lat = feature.geometry.coordinates[1] ?? 0;
        const props = feature.properties;

        if ('cluster' in props && props.cluster) {
          const clusterId = (props.cluster_id ?? 0) as number;
          const count = (props.point_count ?? 0) as number;

          return (
            <Mapbox.MarkerView
              key={`cluster-${clusterId}`}
              id={`cluster-${clusterId}`}
              coordinate={[lng, lat]}
            >
              <Pressable onPress={() => {
                const expansionZoom = Math.min(cluster.getClusterExpansionZoom(clusterId), 16);
                cameraRef.current?.setCamera({
                  centerCoordinate: [lng, lat],
                  zoomLevel: expansionZoom,
                  animationDuration: 300,
                });
              }}>
                <ClusterPin count={count} />
              </Pressable>
            </Mapbox.MarkerView>
          );
        }

        const activity = activityMap.get((props as { id: string }).id);
        if (!activity) return null;

        return (
          <Mapbox.MarkerView
            key={activity.id}
            id={activity.id}
            coordinate={[lng, lat]}
          >
            <Pressable onPress={() => onActivityPress?.(activity)}>
              <ActivityPin activity={activity} />
            </Pressable>
          </Mapbox.MarkerView>
        );
      })}
    </Mapbox.MapView>
  );
}

const styles = StyleSheet.create({
  map: {
    flex: 1,
  },
});
