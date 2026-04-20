import { useState, useMemo, useCallback, useRef, useEffect } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import Mapbox from '@rnmapbox/maps';
import Supercluster from 'supercluster';
import { type NearbyActivity } from '@/services/activity-service';
import { ActivityPin, ACTIVITY_PIN_ANCHOR } from './activity-pin';
import { ClusterPin } from './cluster-pin';
import { MapPinIcon } from './map-pin';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

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

export interface MapPin {
  id: string;
  coordinate: [number, number];
  color: string;
  label?: string;
}

interface MapViewProps {
  center?: [number, number];
  zoom?: number;
  activities?: NearbyActivity[];
  routeLine?: [number, number][];
  pins?: MapPin[];
  userLocation?: [number, number] | null;
  selectedActivity?: NearbyActivity | null;
  popupContent?: React.ReactNode;
  tapMarker?: [number, number] | null;
  tapMarkerContent?: React.ReactNode;
  onActivityPress?: (activity: NearbyActivity) => void;
  onPinPress?: (pin: MapPin) => void;
  onMapPress?: (lng: number, lat: number) => void;
  onBoundsChange?: (bounds: MapBounds) => void;
  flyTo?: { coordinate: [number, number]; key: number; offsetRatio?: { x?: number; y?: number }; zoom?: number } | null;
}

type ActivityPoint = Supercluster.PointFeature<{ id: string }>;

export function JuntoMapView({
  center = DEFAULT_CENTER,
  zoom = DEFAULT_ZOOM,
  activities = [],
  routeLine,
  pins = [],
  userLocation,
  selectedActivity,
  popupContent,
  tapMarker,
  tapMarkerContent,
  onActivityPress,
  onPinPress,
  onMapPress,
  onBoundsChange,
  flyTo,
}: MapViewProps) {
  const colors = useColors();
  const [currentZoom, setCurrentZoom] = useState(zoom);
  const [bounds, setBounds] = useState<[number, number, number, number]>([-180, -90, 180, 90]);
  const cameraRef = useRef<Mapbox.Camera>(null);
  const centerApplied = useRef<string>('');
  const styles = useMemo(() => createStyles(colors), [colors]);

  // Follow `center` prop updates (e.g. GPS resolved after initial mount).
  // Also: force a tiny camera bump on first mount so onCameraChanged fires
  // (Mapbox sometimes skips the initial event, which leaves bounds stale
  // and prevents the first activity search from running).
  useEffect(() => {
    const key = `${center[0]},${center[1]}`;
    if (!cameraRef.current || centerApplied.current === key) return;
    const isFirst = centerApplied.current === '';
    centerApplied.current = key;
    if (isFirst && !onBoundsChange) return;

    // Sometimes Mapbox skips the first onCameraChanged event, which leaves
    // bounds stale and blocks the initial activity fetch. Bump the camera
    // multiple times at increasing delays to maximize the chance one of them
    // fires the event.
    const timers: ReturnType<typeof setTimeout>[] = [];
    const delays = isFirst ? [250, 1000, 2500] : [0];
    for (const delay of delays) {
      timers.push(setTimeout(() => {
        cameraRef.current?.setCamera({
          centerCoordinate: isFirst
            ? [center[0] + (delay / 100000), center[1]]
            : center,
          zoomLevel: zoom,
          animationDuration: isFirst ? 0 : 300,
        });
      }, delay));
    }
    return () => timers.forEach(clearTimeout);
  }, [center, zoom, onBoundsChange]);

  const activityMap = useMemo(
    () => new Map(activities.map((a) => [a.id, a])),
    [activities],
  );

  const cluster = useMemo(() => {
    const sc = new Supercluster<{ id: string }>({
      radius: 60,
      maxZoom: 20,
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

  useEffect(() => {
    if (flyTo && cameraRef.current) {
      const targetZoom = flyTo.zoom ?? Math.max(13, currentZoom);
      // Approximate viewport span in degrees at the target zoom (Web Mercator).
      // ~360 / 2^zoom is the longitudinal width of one base tile across the screen.
      const viewportLngSpan = 360 / Math.pow(2, targetZoom);
      const viewportLatSpan = viewportLngSpan * Math.cos((flyTo.coordinate[1] * Math.PI) / 180);
      const offsetX = (flyTo.offsetRatio?.x ?? 0) * viewportLngSpan;
      const offsetY = (flyTo.offsetRatio?.y ?? 0) * viewportLatSpan;
      cameraRef.current.setCamera({
        centerCoordinate: [flyTo.coordinate[0] + offsetX, flyTo.coordinate[1] + offsetY],
        zoomLevel: targetZoom,
        animationDuration: 1000,
        animationMode: 'flyTo',
      });
    }
  }, [flyTo?.key]);

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


      {routeLine && routeLine.length >= 2 && (
        <Mapbox.ShapeSource
          id="route-line"
          shape={{
            type: 'Feature',
            geometry: { type: 'LineString', coordinates: routeLine },
            properties: {},
          }}
        >
          <Mapbox.LineLayer
            id="route-line-layer"
            style={{
              lineColor: '#FFFFFF',
              lineWidth: 2,
              lineDasharray: [4, 3],
              lineOpacity: 0.7,
            }}
          />
        </Mapbox.ShapeSource>
      )}

      {userLocation && (
        <Mapbox.MarkerView id="user-location" coordinate={userLocation}>
          <View style={styles.userDotOuter}>
            <View style={styles.userDotInner} />
          </View>
        </Mapbox.MarkerView>
      )}

      {tapMarker && (
        <Mapbox.MarkerView id="tap-marker" coordinate={tapMarker} anchor={{ x: 0.5, y: 0 }}>
          <View>{tapMarkerContent ?? <Text style={styles.tapMarker}>✕</Text>}</View>
        </Mapbox.MarkerView>
      )}

      {pins.map((pin) => (
        <Mapbox.MarkerView key={pin.id} id={pin.id} coordinate={pin.coordinate}>
          <Pressable onPress={() => onPinPress?.(pin)}>
            <View style={styles.labeledPin}>
              <MapPinIcon color={pin.color} />
              {pin.label && (
                <View style={[styles.pinLabel, { backgroundColor: pin.color }]}>
                  <Text style={styles.pinLabelText}>{pin.label}</Text>
                </View>
              )}
            </View>
          </Pressable>
        </Mapbox.MarkerView>
      ))}

      {[...clusters]
        .sort((a, b) => {
          // Selected activity rendered last so its popup sits on top of other pins
          const aSel = !('cluster' in a.properties && a.properties.cluster) && (a.properties as { id: string }).id === selectedActivity?.id;
          const bSel = !('cluster' in b.properties && b.properties.cluster) && (b.properties as { id: string }).id === selectedActivity?.id;
          if (aSel === bSel) return 0;
          return aSel ? 1 : -1;
        })
        .map((feature) => {
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
                const expansionZoom = Math.min(cluster.getClusterExpansionZoom(clusterId) + 1, 20);
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

        const isSelected = selectedActivity?.id === activity.id;
        const viewCenter = (bounds[0] + bounds[2]) / 2;
        const isOnRight = lng > viewCenter;

        return (
          <Mapbox.MarkerView
            key={activity.id}
            id={activity.id}
            coordinate={[lng, lat]}
            anchor={ACTIVITY_PIN_ANCHOR}
            allowOverlap={isSelected}
          >
            <View style={isSelected ? { elevation: 999, zIndex: 999 } : undefined}>
              <Pressable onPress={() => {
                onActivityPress?.(activity);
              }}>
                <ActivityPin activity={activity} />
              </Pressable>
            </View>
          </Mapbox.MarkerView>
        );
      })}

      {/* Popup rendered as a separate MarkerView AFTER all pins so it always stacks on top */}
      {selectedActivity && popupContent && (() => {
        const popupOnRight = selectedActivity.lng <= (bounds[0] + bounds[2]) / 2;
        // Anchor on the side facing the pin so the popup extends away from it
        const anchor = popupOnRight ? { x: 0, y: 0.5 } : { x: 1, y: 0.5 };
        return (
          <Mapbox.MarkerView
            key={`popup-${selectedActivity.id}`}
            id={`popup-${selectedActivity.id}`}
            coordinate={[selectedActivity.lng, selectedActivity.lat]}
            allowOverlap
            anchor={anchor}
          >
            <View
              style={popupOnRight ? { marginLeft: 30 } : { marginRight: 30 }}
              pointerEvents="box-none"
            >
              {popupContent}
            </View>
          </Mapbox.MarkerView>
        );
      })()}
    </Mapbox.MapView>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  map: {
    flex: 1,
  },
  tapMarker: {
    color: colors.error,
    fontSize: 24,
    fontWeight: 'bold',
    textAlign: 'center',
  },
  userDotOuter: {
    width: 22,
    height: 22,
    borderRadius: 11,
    backgroundColor: 'rgba(66, 133, 244, 0.25)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  userDotInner: {
    width: 14,
    height: 14,
    borderRadius: 7,
    backgroundColor: '#4285F4',
    borderWidth: 2.5,
    borderColor: '#fff',
  },
  labeledPin: {
    alignItems: 'center',
  },
  pinLabel: {
    marginTop: -2,
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
  },
  pinLabelText: {
    color: '#fff',
    fontSize: 10,
    fontWeight: 'bold',
  },
});
