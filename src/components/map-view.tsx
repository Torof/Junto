import { useState, useMemo, useCallback, useRef, useEffect } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import Mapbox from '@rnmapbox/maps';
import Supercluster from 'supercluster';
import { type NearbyActivity } from '@/services/activity-service';
import { type NearbyPro } from '@/services/pro-service';
import { type ProOffering } from '@/services/pro-offering-service';
import { ActivityPin, ACTIVITY_PIN_ANCHOR } from './activity-pin';
import { ProPin, PRO_PIN_ANCHOR } from './pro-pin';
import { ProOfferingPin, PRO_OFFERING_PIN_ANCHOR } from './pro-offering-pin';
import { ClusterPin } from './cluster-pin';
import { MapPinIcon, MAP_PIN_ANCHOR } from './map-pin';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { circlePolygon } from '@/utils/geo';

const MAPBOX_TOKEN = process.env.EXPO_PUBLIC_MAPBOX_ACCESS_TOKEN;

if (!MAPBOX_TOKEN) {
  throw new Error('Missing EXPO_PUBLIC_MAPBOX_ACCESS_TOKEN in .env');
}

Mapbox.setAccessToken(MAPBOX_TOKEN);
Mapbox.setTelemetryEnabled(false);

import { useMapStyleStore, MAP_STYLE_URLS, MAP_STYLE_JSONS, MAP_STYLE_ATTRIBUTIONS } from '@/store/map-style-store';
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
  pros?: NearbyPro[];
  proOfferings?: ProOffering[];
  routeLine?: [number, number][];
  pins?: MapPin[];
  userLocation?: [number, number] | null;
  selectedActivity?: NearbyActivity | null;
  popupContent?: React.ReactNode;
  tapMarker?: [number, number] | null;
  tapMarkerContent?: React.ReactNode;
  onActivityPress?: (activity: NearbyActivity) => void;
  onProPress?: (pro: NearbyPro) => void;
  onProOfferingPress?: (offering: ProOffering) => void;
  onPinPress?: (pin: MapPin) => void;
  onMapPress?: (lng: number, lat: number) => void;
  onBoundsChange?: (bounds: MapBounds) => void;
  onStuckClusterPress?: (activities: NearbyActivity[]) => void;
  flyTo?: { coordinate: [number, number]; key: number; offsetRatio?: { x?: number; y?: number }; zoom?: number } | null;
  compassEnabled?: boolean;
  // Radius filter overlay — draws a tinted circle around radiusCenter
  // showing the search-radius area. Both must be set to render.
  radiusKm?: number | null;
  radiusCenter?: [number, number] | null;
}

type ActivityPoint = Supercluster.PointFeature<{ id: string }>;

export function JuntoMapView({
  center = DEFAULT_CENTER,
  zoom = DEFAULT_ZOOM,
  activities = [],
  pros = [],
  proOfferings = [],
  routeLine,
  pins = [],
  userLocation,
  selectedActivity,
  popupContent,
  tapMarker,
  tapMarkerContent,
  onActivityPress,
  onProPress,
  onProOfferingPress,
  onPinPress,
  onMapPress,
  onBoundsChange,
  onStuckClusterPress,
  flyTo,
  compassEnabled = true,
  radiusKm,
  radiusCenter,
}: MapViewProps) {
  const colors = useColors();
  const mapStyleKey = useMapStyleStore((s) => s.style);
  const [currentZoom, setCurrentZoom] = useState(zoom);
  const [bounds, setBounds] = useState<[number, number, number, number]>([-180, -90, 180, 90]);
  const cameraRef = useRef<Mapbox.Camera>(null);
  const centerApplied = useRef<string>('');
  const lastCamera = useRef<{ center: [number, number]; zoom: number } | null>(null);
  const styles = useMemo(() => createStyles(colors), [colors]);

  // When the radius filter changes, fit the camera to its bounding box so
  // the visible map matches the active filter. Debounced so a slider drag
  // doesn't trigger a camera move on every step. Cleared (null) keeps the
  // user's current view untouched.
  useEffect(() => {
    if (radiusKm === null || radiusKm === undefined || radiusKm <= 0 || !radiusCenter) return;
    const id = setTimeout(() => {
      const [lng, lat] = radiusCenter;
      const halfDeltaLat = radiusKm / 110.574; // approx km-per-deg-lat
      const halfDeltaLng = halfDeltaLat / Math.max(Math.cos((lat * Math.PI) / 180), 0.01);
      cameraRef.current?.fitBounds(
        [lng + halfDeltaLng, lat + halfDeltaLat],
        [lng - halfDeltaLng, lat - halfDeltaLat],
        60,
        700,
      );
    }, 400);
    return () => clearTimeout(id);
  }, [radiusKm, radiusCenter]);

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

  // Pros get their own Supercluster — distinct from activities so a
  // mixed-content cluster pin can't happen (pro vs activity is a
  // different mental model; clustering them together would be
  // ambiguous on tap).
  const proMap = useMemo(
    () => new Map(pros.map((p) => [p.user_id, p])),
    [pros],
  );

  const proCluster = useMemo(() => {
    const sc = new Supercluster<{ id: string }>({
      radius: 60,
      maxZoom: 20,
    });
    const points: Supercluster.PointFeature<{ id: string }>[] = pros.map((p) => ({
      type: 'Feature',
      geometry: { type: 'Point', coordinates: [p.primary_lng, p.primary_lat] },
      properties: { id: p.user_id },
    }));
    sc.load(points);
    return sc;
  }, [pros]);

  const proClusters = useMemo(
    () => proCluster.getClusters(bounds, Math.floor(currentZoom)),
    [proCluster, bounds, currentZoom],
  );

  // Pro offerings — separate Supercluster instance from activities and
  // pro storefronts. Same rationale: mixed-content clusters would be
  // ambiguous on tap. Same 60px radius for visual consistency.
  const offeringMap = useMemo(
    () => new Map(proOfferings.map((o) => [o.id, o])),
    [proOfferings],
  );

  const offeringCluster = useMemo(() => {
    const sc = new Supercluster<{ id: string }>({
      radius: 60,
      maxZoom: 20,
    });
    const points: Supercluster.PointFeature<{ id: string }>[] = proOfferings.map((o) => ({
      type: 'Feature',
      geometry: { type: 'Point', coordinates: [o.lng, o.lat] },
      properties: { id: o.id },
    }));
    sc.load(points);
    return sc;
  }, [proOfferings]);

  const offeringClusters = useMemo(
    () => offeringCluster.getClusters(bounds, Math.floor(currentZoom)),
    [offeringCluster, bounds, currentZoom],
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
    const cLng = center[0] ?? 0;
    const cLat = center[1] ?? 0;
    lastCamera.current = { center: [cLng, cLat], zoom: state.properties.zoom };
    onBoundsChange?.({
      swLng, swLat, neLng, neLat,
      centerLng: cLng,
      centerLat: cLat,
    });
  }, [onBoundsChange]);

  // Keep the latest user GPS / center / zoom in a ref so the style-change
  // effect below can read them without firing on every location update.
  const fallbackRef = useRef<{ center: [number, number]; zoom: number }>({ center, zoom });
  useEffect(() => {
    fallbackRef.current = { center: userLocation ?? center, zoom };
  }, [userLocation, center, zoom]);

  // On style change, the underlying GL context reloads and the camera may
  // snap back to defaults (lat/lng 0 = gulf of Guinea). Restore the last
  // known camera; if we never moved the camera yet, fall back to the user's
  // GPS location (or the initial center prop).
  useEffect(() => {
    const saved = lastCamera.current ?? fallbackRef.current;
    const t = setTimeout(() => {
      cameraRef.current?.setCamera({
        centerCoordinate: saved.center,
        zoomLevel: saved.zoom,
        animationDuration: 0,
      });
    }, 300);
    return () => clearTimeout(t);
  }, [mapStyleKey]);

  const mapView = (
    <Mapbox.MapView
      style={styles.map}
      styleURL={MAP_STYLE_JSONS[mapStyleKey] ? undefined : MAP_STYLE_URLS[mapStyleKey]}
      styleJSON={MAP_STYLE_JSONS[mapStyleKey]}
      logoEnabled={false}
      attributionEnabled={false}
      compassEnabled={compassEnabled}
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


      {radiusKm !== null && radiusKm !== undefined && radiusKm > 0 && radiusCenter && (
        <Mapbox.ShapeSource
          id="radius-circle"
          shape={{
            type: 'Feature',
            properties: {},
            geometry: {
              type: 'Polygon',
              coordinates: [circlePolygon(radiusCenter[0], radiusCenter[1], radiusKm)],
            },
          }}
        >
          <Mapbox.FillLayer
            id="radius-circle-fill"
            style={{ fillColor: colors.cta, fillOpacity: 0.08 }}
          />
          <Mapbox.LineLayer
            id="radius-circle-line"
            style={{ lineColor: colors.cta, lineWidth: 1.5, lineOpacity: 0.9 }}
          />
        </Mapbox.ShapeSource>
      )}

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
            style={routeLine.length > 2
              ? { lineColor: '#F4642A', lineWidth: 3.5, lineOpacity: 0.9, lineJoin: 'round', lineCap: 'round' }
              : { lineColor: '#FFFFFF', lineWidth: 2, lineDasharray: [4, 3], lineOpacity: 0.7 }}
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
        <Mapbox.MarkerView key={pin.id} id={pin.id} coordinate={pin.coordinate} anchor={MAP_PIN_ANCHOR}>
          <Pressable onPress={() => onPinPress?.(pin)} hitSlop={10}>
            <MapPinIcon color={pin.color} />
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
                const expansionZoom = cluster.getClusterExpansionZoom(clusterId);
                const targetZoom = Math.min(expansionZoom + 1, 20);
                // Stuck cluster: zooming further wouldn't break it apart.
                // Fall through to the drawer with just the leaf activities.
                if (targetZoom <= currentZoom + 0.1 && onStuckClusterPress) {
                  const leaves = cluster.getLeaves(clusterId, Infinity);
                  const stuckActivities = leaves
                    .map((leaf) => activityMap.get((leaf.properties as { id: string }).id))
                    .filter((a): a is NearbyActivity => a !== undefined);
                  onStuckClusterPress(stuckActivities);
                  return;
                }
                cameraRef.current?.setCamera({
                  centerCoordinate: [lng, lat],
                  zoomLevel: targetZoom,
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

      {/* Pro pins — clustered separately from activities so a tap on a
          group never mixes the two entity types. Cluster pin reuses
          the activity ClusterPin shape since the visual idiom carries
          (a number-pill), but the geographic location is the
          disambiguator (no activity pin sits at the same coord). */}
      {proClusters.map((c) => {
        const [lng, lat] = c.geometry.coordinates as [number, number];
        const props = c.properties as Supercluster.ClusterProperties & { id?: string };
        if (props.cluster) {
          const count = props.point_count;
          const clusterId = props.cluster_id;
          return (
            <Mapbox.MarkerView
              key={`pro-cluster-${clusterId}`}
              id={`pro-cluster-${clusterId}`}
              coordinate={[lng, lat]}
              anchor={{ x: 0.5, y: 0.5 }}
            >
              <Pressable onPress={() => {
                const expansionZoom = proCluster.getClusterExpansionZoom(clusterId);
                const targetZoom = Math.min(expansionZoom + 1, 20);
                cameraRef.current?.setCamera({
                  centerCoordinate: [lng, lat],
                  zoomLevel: targetZoom,
                  animationDuration: 300,
                });
              }}>
                <ClusterPin count={count} />
              </Pressable>
            </Mapbox.MarkerView>
          );
        }

        const pro = proMap.get((props as { id: string }).id);
        if (!pro) return null;

        return (
          <Mapbox.MarkerView
            key={`pro-${pro.user_id}`}
            id={`pro-${pro.user_id}`}
            coordinate={[lng, lat]}
            anchor={PRO_PIN_ANCHOR}
          >
            <Pressable onPress={() => onProPress?.(pro)}>
              <ProPin displayName={pro.display_name} pinImageUrl={pro.pin_image_url} />
            </Pressable>
          </Mapbox.MarkerView>
        );
      })}

      {/* Pro offering pins — third independent Supercluster instance.
          Lozenge silhouette differentiates from the activity teardrop
          and the pro storefront square. */}
      {offeringClusters.map((c) => {
        const [lng, lat] = c.geometry.coordinates as [number, number];
        const props = c.properties as Supercluster.ClusterProperties & { id?: string };
        if (props.cluster) {
          const count = props.point_count;
          const clusterId = props.cluster_id;
          return (
            <Mapbox.MarkerView
              key={`offering-cluster-${clusterId}`}
              id={`offering-cluster-${clusterId}`}
              coordinate={[lng, lat]}
              anchor={{ x: 0.5, y: 0.5 }}
            >
              <Pressable onPress={() => {
                const expansionZoom = offeringCluster.getClusterExpansionZoom(clusterId);
                const targetZoom = Math.min(expansionZoom + 1, 20);
                cameraRef.current?.setCamera({
                  centerCoordinate: [lng, lat],
                  zoomLevel: targetZoom,
                  animationDuration: 300,
                });
              }}>
                <ClusterPin count={count} />
              </Pressable>
            </Mapbox.MarkerView>
          );
        }

        const offering = offeringMap.get((props as { id: string }).id);
        if (!offering) return null;

        return (
          <Mapbox.MarkerView
            key={`offering-${offering.id}`}
            id={`offering-${offering.id}`}
            coordinate={[lng, lat]}
            anchor={PRO_OFFERING_PIN_ANCHOR}
          >
            <Pressable onPress={() => onProOfferingPress?.(offering)}>
              <ProOfferingPin offering={offering} />
            </Pressable>
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

  const attribution = MAP_STYLE_ATTRIBUTIONS[mapStyleKey];
  if (attribution) {
    return (
      <View style={styles.mapWrapper}>
        {mapView}
        <View style={styles.attributionPill} pointerEvents="none">
          <Text style={styles.attributionText}>{attribution}</Text>
        </View>
      </View>
    );
  }
  return mapView;
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  map: {
    flex: 1,
  },
  mapWrapper: { flex: 1 },
  attributionPill: {
    position: 'absolute',
    bottom: 4, left: 4,
    paddingHorizontal: 6, paddingVertical: 2,
    backgroundColor: 'rgba(0,0,0,0.55)',
    borderRadius: 4,
  },
  attributionText: {
    color: '#FFFFFF',
    fontSize: 9,
    fontWeight: '500',
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
});
