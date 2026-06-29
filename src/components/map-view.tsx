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
import { SPORT_CATEGORY_COLORS } from '@/utils/sport-category-color';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';

const MAPBOX_TOKEN = process.env.EXPO_PUBLIC_MAPBOX_ACCESS_TOKEN;

if (!MAPBOX_TOKEN) {
  throw new Error('Missing EXPO_PUBLIC_MAPBOX_ACCESS_TOKEN in .env');
}

Mapbox.setAccessToken(MAPBOX_TOKEN);
Mapbox.setTelemetryEnabled(false);

import { useMapStyleStore, MAP_STYLE_URLS, MAP_STYLE_JSONS, MAP_STYLE_ATTRIBUTIONS } from '@/store/map-style-store';
const DEFAULT_CENTER: [number, number] = [6.6323, 44.8967];
const DEFAULT_ZOOM = 10;

// On-map label zoom gates (pin system v4). Below NAME, pins only. At NAME the
// name drops onto the map (pin color, white halo); at DETAIL the second line
// (spots / schedule) appears. Tune on-device.
const LABEL_NAME_ZOOM = 12.5;
const LABEL_DETAIL_ZOOM = 14;

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
  // Pro / offering pins use the same pin-anchored tooltip pattern as
  // activities. Setting any of these renders a popup next to the
  // matching pin. Mutually exclusive in practice (parent state),
  // though the component renders all that are non-null.
  selectedPro?: NearbyPro | null;
  selectedOffering?: ProOffering | null;
  // Id of the pin currently in "peeked" mode (highlighted by a card
  // tap in the bottom-sheet list). The matching pin scales up to draw
  // the eye; no tooltip because the originating card already shows
  // the info. Separate from the selected* states, which govern the
  // popup-on-pin-tap flow.
  highlightedPinId?: string | null;
  popupContent?: React.ReactNode;
  proPopupContent?: React.ReactNode;
  offeringPopupContent?: React.ReactNode;
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

// Single point shape with a type discriminator. The unified Supercluster
// groups activities, pros, and offerings by spatial proximity regardless
// of type — a cluster shows total count; at expansion zoom, individual
// typed pins emerge (teardrop / square / hexagon).
type PinType = 'activity' | 'pro' | 'offering';
type PinPointProps = { type: PinType; id: string };
type PinPoint = Supercluster.PointFeature<PinPointProps>;

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
  selectedPro,
  selectedOffering,
  highlightedPinId,
  popupContent,
  proPopupContent,
  offeringPopupContent,
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
  // Once the user takes camera control (taps a pin/cluster → flyTo/setCamera),
  // the startup centre-bumps + late-GPS follow must stop yanking the camera back.
  const cameraTouched = useRef(false);
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
        // The user has grabbed the camera (tapped a pin/cluster) — don't
        // rewind their zoom with a late startup bump or GPS-follow.
        if (cameraTouched.current) return;
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

  // Per-type lookup maps so we can fetch the original entity from a
  // PinPoint's (type, id) pair when rendering individual pins. The
  // unified Supercluster only carries lightweight `{type, id}` per
  // point — the full row stays here.
  const activityMap = useMemo(
    () => new Map(activities.map((a) => [a.id, a])),
    [activities],
  );
  const proMap = useMemo(
    () => new Map(pros.map((p) => [p.user_id, p])),
    [pros],
  );
  const offeringMap = useMemo(
    () => new Map(proOfferings.map((o) => [o.id, o])),
    [proOfferings],
  );

  // Single Supercluster instance covering all three entity types. A
  // cluster pin at low zoom shows the total count regardless of type;
  // tapping zooms to expansion so the typed individual pins emerge.
  const cluster = useMemo(() => {
    const sc = new Supercluster<PinPointProps>({
      // "See what's around at a glance" is the product. History: 60px
      // merged pins long before they'd overlap; 38 (≈ one pin width) let
      // near-neighbours kiss at the edges, which read as too busy; 44 still
      // declustered too eagerly. 50 ≈ 1.3 pin widths — pins only split once
      // there's a real gap between them, so the declustered field stays
      // clean. Dial down (44/40) for more declustering, up (56) if busy.
      radius: 48,
      maxZoom: 20,
    });
    const points: PinPoint[] = [
      ...activities.map<PinPoint>((a) => ({
        type: 'Feature',
        geometry: { type: 'Point', coordinates: [a.lng, a.lat] },
        properties: { type: 'activity', id: a.id },
      })),
      ...pros.map<PinPoint>((p) => ({
        type: 'Feature',
        geometry: { type: 'Point', coordinates: [p.primary_lng, p.primary_lat] },
        properties: { type: 'pro', id: p.user_id },
      })),
      ...proOfferings.map<PinPoint>((o) => ({
        type: 'Feature',
        geometry: { type: 'Point', coordinates: [o.lng, o.lat] },
        properties: { type: 'offering', id: o.id },
      })),
    ];
    sc.load(points);
    return sc;
  }, [activities, pros, proOfferings]);

  const clusters = useMemo(
    // round (not floor) so declustering happens ~half a zoom level earlier
    // — floor made pins feel "stuck" clustered until a full level crossed.
    () => cluster.getClusters(bounds, Math.round(currentZoom)),
    [cluster, bounds, currentZoom],
  );

  // Google-style on-map labels: a SymbolLayer fed by the DECLUSTERED points
  // (cluster bubbles get none). Native collision + zoom-stepping declutter it;
  // content is type-specific — sortie = when+spots, offering = title+schedule,
  // pro page = name. Color matches the pin's universe (pros fall back to the
  // pro blue). Ratings wait until the nearby views expose an aggregate.
  const labelShape = useMemo(() => {
    const features = clusters.flatMap((f) => {
      const p = f.properties as PinPointProps | (Supercluster.ClusterProperties & PinPointProps);
      if ('cluster' in p && p.cluster) return [];
      const coords = f.geometry.coordinates as [number, number];
      let name = '';
      let detail = '';
      let color: string = colors.pinProBackground;
      const kind = p.type;
      if (p.type === 'activity') {
        const a = activityMap.get(p.id);
        if (!a) return [];
        name = dayjs(a.starts_at).locale('fr').format('ddd H[h]mm').replace('.', '');
        const left = a.max_participants != null
          ? Math.max(0, a.max_participants - a.participant_count)
          : null;
        detail = left != null ? `${left} pl` : '';
        color = SPORT_CATEGORY_COLORS[a.sport_category] ?? colors.cta;
      } else if (p.type === 'pro') {
        const pr = proMap.get(p.id);
        if (!pr) return [];
        name = pr.display_name;
        color = (pr.pin_icon && SPORT_CATEGORY_COLORS[pr.pin_icon]) || colors.pinProBackground;
      } else {
        const o = offeringMap.get(p.id);
        if (!o) return [];
        name = o.title;
        detail = o.schedule_text ?? '';
        color = SPORT_CATEGORY_COLORS[o.sport_category] ?? colors.pinProBackground;
      }
      return [{
        type: 'Feature' as const,
        geometry: { type: 'Point' as const, coordinates: coords },
        properties: { name, detail, color, kind },
      }];
    });
    return { type: 'FeatureCollection' as const, features };
  }, [clusters, activityMap, proMap, offeringMap, colors]);

  useEffect(() => {
    if (flyTo && cameraRef.current) {
      cameraTouched.current = true;
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

      {/* On-map labels — colored text + white halo, native collision +
          zoom-stepping (names at NAME zoom, +detail at DETAIL zoom). Rides
          the declustered points; sits under the MarkerView pins. */}
      <Mapbox.ShapeSource id="pin-labels" shape={labelShape}>
        <Mapbox.SymbolLayer
          id="pin-labels-layer"
          minZoomLevel={LABEL_NAME_ZOOM}
          style={{
            textField: [
              'step', ['zoom'],
              ['get', 'name'],
              LABEL_DETAIL_ZOOM,
              ['case',
                ['>', ['length', ['coalesce', ['get', 'detail'], '']], 0],
                ['concat', ['get', 'name'], '\n', ['get', 'detail']],
                ['get', 'name'],
              ],
            ],
            textColor: ['get', 'color'],
            textHaloColor: '#FFFFFF',
            textHaloWidth: 1.6,
            textHaloBlur: 0.3,
            textSize: 13,
            textFont: ['Open Sans Bold', 'Arial Unicode MS Regular'],
            textAnchor: 'left',
            textOffset: ['match', ['get', 'kind'],
              'pro', ['literal', [1.4, -2.6]],
              'offering', ['literal', [1.4, -2.0]],
              ['literal', [1.4, -1.6]],
            ],
            textJustify: 'left',
            textMaxWidth: 9,
            textAllowOverlap: false,
            textOptional: true,
            symbolSortKey: ['match', ['get', 'kind'], 'pro', 0, 'offering', 1, 2],
          }}
        />
      </Mapbox.ShapeSource>

      {userLocation && (
        <Mapbox.MarkerView id="user-location" coordinate={userLocation} allowOverlap>
          <View style={styles.userDotOuter}>
            <View style={styles.userDotInner} />
          </View>
        </Mapbox.MarkerView>
      )}

      {tapMarker && (
        <Mapbox.MarkerView id="tap-marker" coordinate={tapMarker} anchor={{ x: 0.5, y: 0 }} allowOverlap>
          <View>{tapMarkerContent ?? <Text style={styles.tapMarker}>✕</Text>}</View>
        </Mapbox.MarkerView>
      )}

      {pins.map((pin) => (
        <Mapbox.MarkerView key={pin.id} id={pin.id} coordinate={pin.coordinate} anchor={MAP_PIN_ANCHOR} allowOverlap>
          <Pressable onPress={() => onPinPress?.(pin)} hitSlop={10}>
            <MapPinIcon color={pin.color} />
          </Pressable>
        </Mapbox.MarkerView>
      ))}

      {/* Unified render loop. Mixes activity, pro storefront, and pro
          offering pins. Cluster pins show total count regardless of
          type; tap zooms to expansion so typed individual pins emerge. */}
      {[...clusters]
        .sort((a, b) => {
          // Selected activity rendered last so its popup sits on top of other pins
          const aProps = a.properties as PinPointProps | (Supercluster.ClusterProperties & PinPointProps);
          const bProps = b.properties as PinPointProps | (Supercluster.ClusterProperties & PinPointProps);
          const aSel = !('cluster' in aProps && aProps.cluster) && 'type' in aProps && aProps.type === 'activity' && aProps.id === selectedActivity?.id;
          const bSel = !('cluster' in bProps && bProps.cluster) && 'type' in bProps && bProps.type === 'activity' && bProps.id === selectedActivity?.id;
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
              allowOverlap
            >
              <Pressable onPress={() => {
                const leaves = cluster.getLeaves(clusterId, Infinity);
                // Bounding box of every point under this cluster.
                let minLng = Infinity, minLat = Infinity, maxLng = -Infinity, maxLat = -Infinity;
                for (const leaf of leaves) {
                  const llng = leaf.geometry.coordinates[0] ?? 0;
                  const llat = leaf.geometry.coordinates[1] ?? 0;
                  if (llng < minLng) minLng = llng;
                  if (llng > maxLng) maxLng = llng;
                  if (llat < minLat) minLat = llat;
                  if (llat > maxLat) maxLat = llat;
                }
                // ~3e-5° ≈ 3m, below the pin footprint even at max zoom: these
                // points can never visually separate, so hand the leaf
                // ACTIVITIES to the drawer instead (pros/offerings cluster fine
                // via spatial proximity and aren't surfaced here yet).
                const separable = Number.isFinite(minLng) && (maxLng - minLng > 3e-5 || maxLat - minLat > 3e-5);
                if (!separable && onStuckClusterPress) {
                  const stuckActivities = leaves
                    .filter((leaf) => (leaf.properties as PinPointProps).type === 'activity')
                    .map((leaf) => activityMap.get((leaf.properties as PinPointProps).id))
                    .filter((a): a is NearbyActivity => a !== undefined);
                  onStuckClusterPress(stuckActivities);
                  return;
                }
                cameraTouched.current = true;
                if (separable) {
                  // Frame the whole cluster in one tap so its pins spread across
                  // the viewport and decluster at once. (expansionZoom+1 could
                  // land on a sub-cluster — that's what forced the 2nd tap.)
                  cameraRef.current?.fitBounds([maxLng, maxLat], [minLng, minLat], 80, 400);
                } else {
                  cameraRef.current?.setCamera({ centerCoordinate: [lng, lat], zoomLevel: 18, animationDuration: 300 });
                }
              }}>
                <ClusterPin count={count} />
              </Pressable>
            </Mapbox.MarkerView>
          );
        }

        // Individual pin — branch on type for shape + tap handler.
        const pinProps = props as PinPointProps;

        // Highlighted pin shared style — scaled 1.3x and stacked on top.
        // The slight downward drift from center-scaling is a few pixels at
        // this size and reads as "the pin grew up out of the location",
        // which is the right metaphor for the peek state.
        const isHighlighted = highlightedPinId === pinProps.id;
        const highlightStyle = isHighlighted
          ? { transform: [{ scale: 1.3 }], elevation: 998, zIndex: 998 }
          : undefined;

        if (pinProps.type === 'activity') {
          const activity = activityMap.get(pinProps.id);
          if (!activity) return null;
          const isSelected = selectedActivity?.id === activity.id;
          const viewCenter = (bounds[0] + bounds[2]) / 2;
          const isOnRight = lng > viewCenter;
          return (
            <Mapbox.MarkerView
              key={`activity-${activity.id}`}
              id={`activity-${activity.id}`}
              coordinate={[lng, lat]}
              anchor={ACTIVITY_PIN_ANCHOR}
              allowOverlap
            >
              <View style={isSelected ? { elevation: 999, zIndex: 999 } : highlightStyle}>
                <Pressable onPress={() => onActivityPress?.(activity)} hitSlop={14}>
                  <ActivityPin activity={activity} />
                </Pressable>
              </View>
            </Mapbox.MarkerView>
          );
        }

        if (pinProps.type === 'pro') {
          const pro = proMap.get(pinProps.id);
          if (!pro) return null;
          return (
            <Mapbox.MarkerView
              key={`pro-${pro.user_id}`}
              id={`pro-${pro.user_id}`}
              coordinate={[lng, lat]}
              anchor={PRO_PIN_ANCHOR}
              allowOverlap
            >
              <View style={highlightStyle}>
                <Pressable onPress={() => onProPress?.(pro)} hitSlop={14}>
                  <ProPin displayName={pro.display_name} pinIcon={pro.pin_icon} />
                </Pressable>
              </View>
            </Mapbox.MarkerView>
          );
        }

        // pinProps.type === 'offering'
        const offering = offeringMap.get(pinProps.id);
        if (!offering) return null;
        return (
          <Mapbox.MarkerView
            key={`offering-${offering.id}`}
            id={`offering-${offering.id}`}
            coordinate={[lng, lat]}
            anchor={PRO_OFFERING_PIN_ANCHOR}
            allowOverlap
          >
            <View style={highlightStyle}>
              <Pressable onPress={() => onProOfferingPress?.(offering)} hitSlop={14}>
                <ProOfferingPin offering={offering} />
              </Pressable>
            </View>
          </Mapbox.MarkerView>
        );
      })}

      {/* Popups rendered as separate MarkerViews AFTER all pins so
          they always stack on top. Same auto-anchor logic for all
          three: popup extends to the side away from the screen edge
          to avoid clipping. */}
      {selectedActivity && popupContent && (() => {
        const popupOnRight = selectedActivity.lng <= (bounds[0] + bounds[2]) / 2;
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

      {selectedPro && proPopupContent && (() => {
        const popupOnRight = selectedPro.primary_lng <= (bounds[0] + bounds[2]) / 2;
        const anchor = popupOnRight ? { x: 0, y: 0.5 } : { x: 1, y: 0.5 };
        return (
          <Mapbox.MarkerView
            key={`popup-pro-${selectedPro.user_id}`}
            id={`popup-pro-${selectedPro.user_id}`}
            coordinate={[selectedPro.primary_lng, selectedPro.primary_lat]}
            allowOverlap
            anchor={anchor}
          >
            <View
              style={popupOnRight ? { marginLeft: 26 } : { marginRight: 26 }}
              pointerEvents="box-none"
            >
              {proPopupContent}
            </View>
          </Mapbox.MarkerView>
        );
      })()}

      {selectedOffering && offeringPopupContent && (() => {
        const popupOnRight = selectedOffering.lng <= (bounds[0] + bounds[2]) / 2;
        const anchor = popupOnRight ? { x: 0, y: 0.5 } : { x: 1, y: 0.5 };
        return (
          <Mapbox.MarkerView
            key={`popup-offering-${selectedOffering.id}`}
            id={`popup-offering-${selectedOffering.id}`}
            coordinate={[selectedOffering.lng, selectedOffering.lat]}
            allowOverlap
            anchor={anchor}
          >
            <View
              style={popupOnRight ? { marginLeft: 28 } : { marginRight: 28 }}
              pointerEvents="box-none"
            >
              {offeringPopupContent}
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
