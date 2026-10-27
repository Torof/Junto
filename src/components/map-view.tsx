import { useState, useMemo, useCallback, useRef, useEffect, type ComponentRef, type RefObject } from 'react';
import { View, Pressable, StyleSheet } from 'react-native';
import { AppText } from '@/components/app-text';
import { Calendar, BarChart3 } from 'lucide-react-native';
import Mapbox from '@rnmapbox/maps';
import Supercluster from 'supercluster';
import { type NearbyActivity } from '@/services/activity-service';
import { type NearbyPro } from '@/services/pro-service';
import { type ProOffering } from '@/services/pro-offering-service';
import { ActivityPin, ACTIVITY_PIN_ANCHOR } from './activity-pin';
import { ProPin, PRO_PIN_ANCHOR } from './pro-pin';
import { proPinLook } from '@/utils/pro-pin-look';
import { useSports } from '@/hooks/use-sports';
import { ProOfferingPin, PRO_OFFERING_PIN_ANCHOR } from './pro-offering-pin';
import { ClusterPin, type ClusterSegment } from './cluster-pin';
import { MapPinIcon, MAP_PIN_ANCHOR } from './map-pin';
import { UserLocationDot } from './user-location-dot';
import { useColors } from '@/hooks/use-theme';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import type { AppColors } from '@/constants/colors';
import { circlePolygon } from '@/utils/geo';
import { SPORT_CATEGORY_COLORS } from '@/utils/sport-category-color';
import { formatDifficultySignal } from '@/constants/sport-levels';
import dayjs from 'dayjs';
import i18n from '@/i18n';
import 'dayjs/locale/fr';

import { useMapStyleStore, MAP_STYLE_URLS, MAP_STYLE_JSONS, MAP_STYLE_ATTRIBUTIONS } from '@/store/map-style-store';

const MAPBOX_TOKEN = process.env.EXPO_PUBLIC_MAPBOX_ACCESS_TOKEN;

if (!MAPBOX_TOKEN) {
  throw new Error('Missing EXPO_PUBLIC_MAPBOX_ACCESS_TOKEN in .env');
}

Mapbox.setAccessToken(MAPBOX_TOKEN);
Mapbox.setTelemetryEnabled(false);
const DEFAULT_CENTER: [number, number] = [6.6323, 44.8967];
const DEFAULT_ZOOM = 10;

// On-map label zoom gates (pin system v4). Below NAME, pins only. At NAME the
// name drops onto the map (pin color, white halo); at DETAIL the second line
// (spots / schedule) appears. Tune on-device.
const LABEL_NAME_ZOOM = 10.5;
const LABEL_DETAIL_ZOOM = 11.0;

// Catch-phrase / schedule lines get cut so a single pin can't hog the map.
const truncate = (s: string, n: number) =>
  s.length > n ? `${s.slice(0, n).trimEnd()}…` : s;

// The rating line of a pro label (Scott 2026-10-25): five real star images
// with a thin ink border — gold ones for the rounded rating, pale ones for the
// rest, no halo since images take none — then « · N avis » in ink. Empty when
// there is no review.
type StarImage = 'star-full' | 'star-empty' | '';
const ratingParts = (
  avg: number | null | undefined,
  count: number | null | undefined,
): { stars: [StarImage, StarImage, StarImage, StarImage, StarImage]; rtext: string } => {
  if (!count || avg == null) return { stars: ['', '', '', '', ''], rtext: '' };
  const filled = Math.max(0, Math.min(5, Math.round(Number(avg))));
  const stars = [1, 2, 3, 4, 5].map((i) => (i <= filled ? 'star-full' : 'star-empty')) as [StarImage, StarImage, StarImage, StarImage, StarImage];
  return { stars, rtext: ` · ${i18n.t('pro.page.reviewCount', { count, defaultValue: '{{count}} avis' })}` };
};

// Secondary-line text style (smaller, regular, neutral black) — shared by
// every text section of the detail line.
const SEC = {
  'font-scale': 0.78,
  'text-color': '#1A1A1A',
  'text-font': ['literal', ['Open Sans Regular', 'Arial Unicode MS Regular']],
};

// Inline-icon sections carry no scaling: the native SDK ignores font-scale on
// images, so the icon size is set by the registered image's `scale` instead.
const IMG = {};

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
  // Id of the pin currently in "peeked" mode (highlighted by a card
  // tap in the bottom-sheet list). The matching pin scales up to draw
  // the eye; no tooltip because the originating card already shows
  // the info. Separate from the selected* states, which govern the
  // popup-on-pin-tap flow.
  highlightedPinId?: string | null;
  popupContent?: React.ReactNode;
  tapMarker?: [number, number] | null;
  tapMarkerContent?: React.ReactNode;
  onActivityPress?: (activity: NearbyActivity) => void;
  onProPress?: (pro: NearbyPro) => void;
  onProOfferingPress?: (offering: ProOffering) => void;
  onPinPress?: (pin: MapPin) => void;
  // Render `pins` as GL circle layers instead of MarkerViews — for secondary
  // map instances (modals) where MarkerViews can fail to attach. No taps.
  pinsAsLayers?: boolean;
  onMapPress?: (lng: number, lat: number) => void;
  onBoundsChange?: (bounds: MapBounds) => void;
  flyTo?: { coordinate: [number, number]; key: number; offsetRatio?: { x?: number; y?: number }; zoom?: number } | null;
  compassEnabled?: boolean;
  // Report the map's heading (degrees) so a custom compass button can rotate.
  onHeadingChange?: (heading: number) => void;
  // Bump this to animate the camera back to north (heading 0).
  resetBearingKey?: number;
  // Radius filter overlay — draws a tinted circle around radiusCenter
  // showing the search-radius area. Both must be set to render.
  radiusKm?: number | null;
  radiusCenter?: [number, number] | null;
  // Android rendering surface. Default (true) = SurfaceView, which the
  // tab-bounded carte uses fine. On a full-height edge-to-edge Stack screen
  // SurfaceView latches a too-short height at mount and clips MarkerView pins
  // in a bottom band (Scott 2026-07-12); a TextureView (false) re-measures
  // with its container as it grows, so pass surfaceView={false} there.
  surfaceView?: boolean;
  // Freehand-draw support (trace-draw-modal): expose the underlying MapView so
  // the caller can convert screen px → geo (getCoordinateFromView), and let it
  // lock the map gestures while drawing. All optional/backward-compatible.
  mapViewRef?: RefObject<JuntoMapRef | null>;
  scrollEnabled?: boolean;
  zoomEnabled?: boolean;
  rotateEnabled?: boolean;
  pitchEnabled?: boolean;
}

// Underlying rnmapbox MapView instance type — carries getCoordinateFromView.
export type JuntoMapRef = ComponentRef<typeof Mapbox.MapView>;

// Single point shape with a type discriminator. The unified Supercluster
// groups activities, pros, and offerings by spatial proximity regardless
// of type — a cluster shows total count; at expansion zoom, individual
// typed pins emerge (teardrop / square / hexagon).
type PinType = 'activity' | 'pro' | 'offering';
// `u` = universe key (sport_category / pro pin_icon, '' when none) — summed
// per cluster by Supercluster's map/reduce into `u` counts for the ring.
type PinPointProps = { type: PinType; id: string; u: string };
// u = pins per universe (ring segments); k = a stable name for the cluster:
// the smallest pin key it contains. Supercluster's numeric cluster_id changes
// whenever the index is rebuilt with new data; k does not, so a cluster that
// survives a refetch keeps its marker (updated in place, no blink).
type ClusterAgg = { u: Record<string, number>; k: string };
type PinPoint = Supercluster.PointFeature<PinPointProps>;
type FanLeaf = { props: PinPointProps; lng: number; lat: number };
type FanState = { key: string; center: [number, number]; zoom: number; radiusPx: number; leaves: FanLeaf[]; openedAt: number };

// Fan geometry: radius in screen px by count, one ring up to eight, a second
// ring beyond. Screen px → degrees at the current zoom (Mapbox 512-px tiles:
// 78271.517 · cos(lat) / 2^zoom metres per px).
const FAN_HALO_PAD = 28;
// Below this zoom the fan would open among the neighbours: zoom in to it first.
const FAN_MIN_ZOOM = 15;
// Each pin stays INSIDE the halo and grazes its edge from within (Scott
// 2026-10-27): the top pin touches with the top of its head, the bottom one
// with its tip, a right-hand one with its right side… The pin is taken as a
// box around its head centre (screen px, 40-px drop + outline): half-width,
// height above the head centre, height below it down to the tip.
const FAN_PIN_HALF_W = 18;
const FAN_PIN_ABOVE_HEAD = 17;
const FAN_PIN_BELOW_HEAD = 22;
function fanRadiusPx(n: number): number { return n <= 3 ? 58 : n <= 5 ? 72 : 92; }
function fanLeaves(points: PinPoint[], center: [number, number], zoomLevel: number): { leaves: FanLeaf[]; radiusPx: number } {
  const n = points.length;
  const radiusPx = fanRadiusPx(n);
  const lat = center[1];
  const mPerPx = (78271.517 * Math.cos((lat * Math.PI) / 180)) / Math.pow(2, zoomLevel);
  const degPerPxLng = mPerPx / (111320 * Math.cos((lat * Math.PI) / 180));
  const degPerPxLat = mPerPx / 110540;
  const leaves = points.map((p, i) => {
    const ring = i < 8 ? 0 : 1;
    const inRing = ring === 0 ? Math.min(n, 8) : n - 8;
    const j = ring === 0 ? i : i - 8;
    // The circle the pins graze: the halo's edge (second ring: one pin further out).
    const R = (ring === 0 ? radiusPx : radiusPx + 48) + FAN_HALO_PAD;
    const a = -Math.PI / 2 + (j * 2 * Math.PI) / inRing + (ring === 1 ? Math.PI / inRing : 0);
    const dx = Math.cos(a), dy = Math.sin(a); // screen y grows downward
    // How far the pin's box reaches along its own direction: pull the head
    // centre back by that much so the outermost side just touches the edge.
    const reach = FAN_PIN_HALF_W * Math.abs(dx) + (dy > 0 ? FAN_PIN_BELOW_HEAD * dy : FAN_PIN_ABOVE_HEAD * -dy);
    const rho = R - reach;
    const px = rho * dx;
    const py = rho * dy + FAN_PIN_BELOW_HEAD; // anchor is the tip, below the head centre
    return { props: p.properties, lng: center[0] + px * degPerPxLng, lat: center[1] - py * degPerPxLat };
  });
  return { leaves, radiusPx: n > 8 ? radiusPx + 48 : radiusPx };
}
// Fixed slice order so a cluster's ring reads the same everywhere.
const UNIVERSE_ORDER = ['mountain', 'water', 'air', 'cycling', 'on-foot', 'wellness', ''];

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
  highlightedPinId,
  popupContent,
  tapMarker,
  tapMarkerContent,
  onActivityPress,
  onProPress,
  onProOfferingPress,
  onPinPress,
  pinsAsLayers = false,
  onMapPress,
  onBoundsChange,
  flyTo,
  compassEnabled = true,
  onHeadingChange,
  resetBearingKey,
  radiusKm,
  radiusCenter,
  surfaceView = true,
  mapViewRef,
  scrollEnabled = true,
  zoomEnabled = true,
  rotateEnabled = true,
  pitchEnabled = true,
}: MapViewProps) {
  const colors = useColors();
  const insets = useSafeAreaInsets();
  const mapStyleKey = useMapStyleStore((s) => s.style);
  const [currentZoom, setCurrentZoom] = useState(zoom);
  // The fan (Scott 2026-10-27, mockup « halo »): a cluster whose points share
  // one spot can't be zoomed apart, so its tap spreads the pins on a circle
  // around the point, over a translucent white halo, each pin tappable as
  // usual. Closes on a map tap, a gesture or a zoom change.
  const [fan, setFan] = useState<FanState | null>(null);
  const [bounds, setBounds] = useState<[number, number, number, number]>([-180, -90, 180, 90]);
  const cameraRef = useRef<Mapbox.Camera>(null);
  const centerApplied = useRef<string>('');
  const lastCamera = useRef<{ center: [number, number]; zoom: number } | null>(null);
  // Last (bounds+zoom) actually reported to onBoundsChange — used to skip
  // no-op camera events (onCameraChanged + onMapIdle double-fire, and onMapIdle
  // firing after a pure tap that never moved the camera).
  const lastReported = useRef<{ swLng: number; swLat: number; neLng: number; neLat: number; zoom: number } | null>(null);
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
    // A later centre (stored fix → OS fix → GPS) is re-applied a few times
    // too: a setCamera sent before the map is ready is dropped, and the
    // region-first opening (2026-10-26) sends its first one very early.
    const timers: ReturnType<typeof setTimeout>[] = [];
    const delays = isFirst ? [250, 1000, 2500] : [0, 400, 1500];
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
  //
  // Rebuilt ONLY when the pins themselves change (Scott 2026-10-22): every
  // refetch (pan, zoom end, server « outing changed » ping) hands new arrays
  // with often identical content. A rebuild renumbers every cluster, so their
  // markers were torn down and redrawn — a tenth-of-a-second blink during
  // which a tap was lost, or landed on the activity pin redrawn underneath.
  // A tap on a marker also reaches the map underneath (Mapbox fires the map's
  // onPress on tap-up). The screen then closed a preview or opened the
  // « create here » tooltip, re-rendering the map MID-tap: the cluster blinked
  // and its own press was cancelled (Scott 2026-10-22). Markers stamp the
  // moment a finger lands on them (onPressIn, always earlier) and the map
  // ignores a press that started on a marker.
  const markerTouchAt = useRef(0);
  const stampMarkerTouch = useCallback(() => { markerTouchAt.current = Date.now(); }, []);
  // A pro pin's universe is derived (00557): image → none, universe key,
  // sport key → its category, else the profession's universe. Feeds the
  // cluster ring and the label colour, like sport_category does for outings.
  const { data: sportRows } = useSports();
  const proUniverse = useCallback((p: NearbyPro) => {
    const m = new Map((sportRows ?? []).map((s) => [s.key, s.category]));
    return proPinLook(p, (key) => m.get(key)).universe ?? '';
  }, [sportRows]);
  const clusterCache = useRef<{ sig: string; sc: Supercluster<PinPointProps, ClusterAgg> } | null>(null);
  const cluster = useMemo(() => {
    const sig = [
      activities.map((a) => `a${a.id}:${a.lng}:${a.lat}:${a.sport_category ?? ''}`).join('|'),
      pros.map((p) => `p${p.user_id}:${p.primary_lng}:${p.primary_lat}:${proUniverse(p)}`).join('|'),
      proOfferings.map((o) => `o${o.id}:${o.lng}:${o.lat}:${o.sport_category ?? ''}`).join('|'),
    ].join('#');
    if (clusterCache.current?.sig === sig) return clusterCache.current.sc;
    const sc = new Supercluster<PinPointProps, ClusterAgg>({
      // "See what's around at a glance" is the product. History: 60px
      // merged pins long before they'd overlap; 38 (≈ one pin width) let
      // near-neighbours kiss at the edges, which read as too busy; 44 still
      // declustered too eagerly. 50 ≈ 1.3 pin widths — pins only split once
      // there's a real gap between them, so the declustered field stays
      // clean. Dial down (44/40) for more declustering, up (56) if busy.
      radius: 48,
      maxZoom: 20,
      map: (p) => ({ u: { [p.u]: 1 }, k: `${p.type}:${p.id}` }),
      reduce: (acc, p) => {
        for (const k in p.u) acc.u[k] = (acc.u[k] ?? 0) + (p.u[k] ?? 0);
        if (p.k < acc.k) acc.k = p.k;
      },
    });
    const points: PinPoint[] = [
      ...activities.map<PinPoint>((a) => ({
        type: 'Feature',
        geometry: { type: 'Point', coordinates: [a.lng, a.lat] },
        properties: { type: 'activity', id: a.id, u: a.sport_category ?? '' },
      })),
      ...pros.map<PinPoint>((p) => ({
        type: 'Feature',
        geometry: { type: 'Point', coordinates: [p.primary_lng, p.primary_lat] },
        properties: { type: 'pro', id: p.user_id, u: proUniverse(p) },
      })),
      ...proOfferings.map<PinPoint>((o) => ({
        type: 'Feature',
        geometry: { type: 'Point', coordinates: [o.lng, o.lat] },
        properties: { type: 'offering', id: o.id, u: o.sport_category ?? '' },
      })),
    ];
    sc.load(points);
    clusterCache.current = { sig, sc };
    return sc;
  }, [activities, pros, proOfferings, proUniverse]);

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
    // Fan open: no native label at all — the fan draws its own, above the halo.
    const labelled: (typeof clusters)[number][] = fan ? [] : clusters;
    const features = labelled.flatMap((f) => {
      const p = f.properties as PinPointProps | (Supercluster.ClusterProperties & PinPointProps);
      if ('cluster' in p && p.cluster) return [];
      const coords = f.geometry.coordinates as [number, number];
      let name = '';
      let d2 = '';          // primary detail text (when / schedule / tagline)
      let d2icon = '';      // inline icon leading d2: 'cal' | ''
      let lvl = '';         // UA difficulty signal (km · D+ / level range)
      let lvlicon = '';     // 'lvl' icon before lvl, or ''
      let rtext = '';       // « · N avis » after the stars, or ''
      let stars: [StarImage, StarImage, StarImage, StarImage, StarImage] = ['', '', '', '', ''];
      let color: string = colors.cta;
      const kind = p.type;
      if (p.type === 'activity') {
        // UA: title (universe colour) · 📅 when · 📊 level signal.
        const a = activityMap.get(p.id);
        if (!a) return [];
        const d = dayjs(a.starts_at);
        name = a.title;
        d2 = `${d.format('ddd D MMM')} à ${d.minute() === 0 ? d.format('H[h]') : d.format('H[h]mm')}`;
        d2icon = 'cal';
        lvl = formatDifficultySignal(a.sport_key, a.level, a.distance_km, a.elevation_gain_m, a.level_max);
        lvlicon = lvl ? 'lvl' : '';
        color = SPORT_CATEGORY_COLORS[a.sport_category] ?? colors.cta;
      } else if (p.type === 'pro') {
        // PP: name · ★rating (own line) · catch-phrase (tagline, truncated).
        const pr = proMap.get(p.id);
        if (!pr) return [];
        name = pr.display_name;
        ({ stars, rtext } = ratingParts(pr.avg_rating, pr.review_count));
        d2 = pr.tagline ? truncate(pr.tagline, 28) : '';
        color = SPORT_CATEGORY_COLORS[proUniverse(pr)] ?? colors.textPrimary;
      } else {
        // RA: title · ★rating (own line) · 📅 schedule conditions.
        const o = offeringMap.get(p.id);
        if (!o) return [];
        name = o.title;
        ({ stars, rtext } = ratingParts(o.avg_rating, o.review_count));
        d2 = o.schedule_text ?? '';
        d2icon = d2 ? 'cal' : '';
        color = SPORT_CATEGORY_COLORS[o.sport_category] ?? colors.cta;
      }
      return [{
        type: 'Feature' as const,
        geometry: { type: 'Point' as const, coordinates: coords },
        properties: { id: p.id, name, color, kind, rtext, s1: stars[0], s2: stars[1], s3: stars[2], s4: stars[3], s5: stars[4], d2, d2icon, lvl, lvlicon },
      }];
    });
    return { type: 'FeatureCollection' as const, features };
  }, [clusters, fan, activityMap, proMap, offeringMap, colors, proUniverse]);

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
    // Runs once per request: `key` is bumped by the caller for every flyTo,
    // and the camera must not re-fly when the zoom or the object identity move.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [flyTo?.key]);

  // Reset the map to north when the custom compass button is tapped.
  useEffect(() => {
    if (resetBearingKey && cameraRef.current) {
      cameraRef.current.setCamera({ heading: 0, animationDuration: 300, animationMode: 'easeTo' });
    }
  }, [resetBearingKey]);

  const handleCameraChanged = useCallback((state: Mapbox.MapState) => {
    onHeadingChange?.(state.properties.heading);
    // The user is moving the map: a late GPS fix must not rewind it to the
    // start-up centre (Scott 2026-10-26, the region-first opening).
    if (state.gestures.isGestureActive) cameraTouched.current = true;
    if (fan && Date.now() - fan.openedAt > 800 && (state.gestures.isGestureActive || Math.abs(state.properties.zoom - fan.zoom) > 0.05)) {
      setFan(null);
    }
    const zoom = state.properties.zoom;
    const sw = state.properties.bounds.sw;
    const ne = state.properties.bounds.ne;
    const swLng = sw[0] ?? -180;
    const swLat = sw[1] ?? -90;
    const neLng = ne[0] ?? 180;
    const neLat = ne[1] ?? 90;

    // onCameraChanged and onMapIdle can both fire for the SAME camera state,
    // and onMapIdle even fires after a pure TAP that never moved the camera.
    // Firing onBoundsChange then made the carte clear its tap-to-create tooltip
    // instantly (Scott 2026-07-12). Skip when nothing actually changed.
    const prev = lastReported.current;
    if (prev
      && Math.abs(prev.zoom - zoom) < 1e-4
      && Math.abs(prev.swLng - swLng) < 1e-7
      && Math.abs(prev.swLat - swLat) < 1e-7
      && Math.abs(prev.neLng - neLng) < 1e-7
      && Math.abs(prev.neLat - neLat) < 1e-7) {
      return;
    }
    lastReported.current = { swLng, swLat, neLng, neLat, zoom };

    setCurrentZoom(zoom);
    setBounds([swLng, swLat, neLng, neLat]);
    const center = state.properties.center;
    const cLng = center[0] ?? 0;
    const cLat = center[1] ?? 0;
    lastCamera.current = { center: [cLng, cLat], zoom };
    onBoundsChange?.({
      swLng, swLat, neLng, neLat,
      centerLng: cLng,
      centerLat: cLat,
    });
  }, [fan, onBoundsChange, onHeadingChange]);

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

  // One pin marker per type (shape + tap handler). `suffix` keeps keys unique
  // when the same pin is drawn a second time inside the fan; `beforePress`
  // runs first (the fan closes itself).
  // In the fan the label is a React view beside the pin — the native symbol
  // labels live under every MarkerView, so under the halo (Scott 2026-10-27).
  // Same content as the native labels: title · 📅 when · 📊 level for an
  // outing, title · 📅 schedule for a pro outing, name · tagline for a pro.
  type FanLine = { icon?: 'cal' | 'lvl'; text: string };
  const fanLabelFor = (pinProps: PinPointProps): { name: string; lines: FanLine[]; color: string } | null => {
    if (pinProps.type === 'activity') {
      const a = activityMap.get(pinProps.id); if (!a) return null;
      const d = dayjs(a.starts_at);
      const lvl = formatDifficultySignal(a.sport_key, a.level, a.distance_km, a.elevation_gain_m, a.level_max);
      const lines: FanLine[] = [{ icon: 'cal', text: `${d.format('ddd D MMM')} à ${d.minute() === 0 ? d.format('H[h]') : d.format('H[h]mm')}` }];
      if (lvl) lines.push({ icon: 'lvl', text: lvl });
      return { name: a.title, lines, color: SPORT_CATEGORY_COLORS[a.sport_category] ?? colors.cta };
    }
    if (pinProps.type === 'pro') {
      const pr = proMap.get(pinProps.id); if (!pr) return null;
      return { name: pr.display_name, lines: pr.tagline ? [{ text: truncate(pr.tagline, 28) }] : [], color: colors.textPrimary };
    }
    const o = offeringMap.get(pinProps.id); if (!o) return null;
    return { name: o.title, lines: o.schedule_text ? [{ icon: 'cal', text: o.schedule_text }] : [], color: SPORT_CATEGORY_COLORS[o.sport_category] ?? colors.cta };
  };
  const fanLabel = (pinProps: PinPointProps, side: 'left' | 'right') => {
    const l = fanLabelFor(pinProps);
    if (!l) return null;
    const right = side === 'right';
    return (
      <View pointerEvents="none" style={[styles.fanLabel, right ? styles.fanLabelRight : styles.fanLabelLeft]}>
        <AppText style={[styles.fanLabelName, { color: l.color, textAlign: right ? 'left' : 'right' }]} numberOfLines={2}>{l.name}</AppText>
        {l.lines.map((line, i) => (
          <View key={i} style={[styles.fanLabelRow, !right && styles.fanLabelRowLeft]}>
            {line.icon === 'cal' ? <Calendar size={10} color={colors.textSecondary} strokeWidth={2.4} /> : null}
            {line.icon === 'lvl' ? <BarChart3 size={10} color={colors.textSecondary} strokeWidth={2.4} /> : null}
            <AppText style={styles.fanLabelSub} numberOfLines={1}>{line.text}</AppText>
          </View>
        ))}
      </View>
    );
  };

  const pinMarker = (pinProps: PinPointProps, lng: number, lat: number, suffix = '', beforePress?: () => void, fanSide?: 'left' | 'right') => {
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
          return (
            <Mapbox.MarkerView
              key={`activity-${activity.id}${suffix}`}
              id={`activity-${activity.id}${suffix}`}
              coordinate={[lng, lat]}
              anchor={ACTIVITY_PIN_ANCHOR}
              allowOverlap
            >
              <View style={isSelected ? { elevation: 999, zIndex: 999 } : highlightStyle}>
                <Pressable onPressIn={stampMarkerTouch} onPress={() => { beforePress?.(); onActivityPress?.(activity); }} hitSlop={14}>
                  <ActivityPin activity={activity} />
                </Pressable>
                {fanSide ? fanLabel(pinProps, fanSide) : null}
              </View>
            </Mapbox.MarkerView>
          );
        }

        if (pinProps.type === 'pro') {
          const pro = proMap.get(pinProps.id);
          if (!pro) return null;
          return (
            <Mapbox.MarkerView
              key={`pro-${pro.user_id}${suffix}`}
              id={`pro-${pro.user_id}${suffix}`}
              coordinate={[lng, lat]}
              anchor={PRO_PIN_ANCHOR}
              allowOverlap
            >
              <View style={highlightStyle}>
                <Pressable onPressIn={stampMarkerTouch} onPress={() => { beforePress?.(); onProPress?.(pro); }} hitSlop={14}>
                  <ProPin displayName={pro.display_name} pinIcon={pro.pin_icon} profession={pro.profession} pinImageUrl={pro.pin_image_url} />
                </Pressable>
                {fanSide ? fanLabel(pinProps, fanSide) : null}
              </View>
            </Mapbox.MarkerView>
          );
        }

        // pinProps.type === 'offering'
        const offering = offeringMap.get(pinProps.id);
        if (!offering) return null;
        return (
          <Mapbox.MarkerView
            key={`offering-${offering.id}${suffix}`}
            id={`offering-${offering.id}${suffix}`}
            coordinate={[lng, lat]}
            anchor={PRO_OFFERING_PIN_ANCHOR}
            allowOverlap
          >
            <View style={highlightStyle}>
              <Pressable onPressIn={stampMarkerTouch} onPress={() => { beforePress?.(); onProOfferingPress?.(offering); }} hitSlop={14}>
                <ProOfferingPin offering={offering} />
              </Pressable>
              {fanSide ? fanLabel(pinProps, fanSide) : null}
            </View>
          </Mapbox.MarkerView>
        );
  };

  const mapView = (
    <Mapbox.MapView
      ref={mapViewRef}
      style={styles.map}
      surfaceView={surfaceView}
      scrollEnabled={scrollEnabled}
      zoomEnabled={zoomEnabled}
      rotateEnabled={rotateEnabled}
      pitchEnabled={pitchEnabled}
      styleURL={MAP_STYLE_JSONS[mapStyleKey] ? undefined : MAP_STYLE_URLS[mapStyleKey]}
      styleJSON={MAP_STYLE_JSONS[mapStyleKey]}
      logoEnabled={false}
      attributionEnabled={false}
      compassEnabled={compassEnabled}
      compassViewMargins={{ x: 12, y: insets.top + 2 }}
      scaleBarEnabled={false}
      onCameraChanged={handleCameraChanged}
      // onCameraChanged is throttled and can miss the FINAL settle frame, so
      // bounds/zoom (→ the cluster set) stay stale until the next gesture —
      // pins near the edge vanish and a zoom-in doesn't re-expand until you
      // nudge the map again (Scott 2026-07-12). onMapIdle fires once the
      // camera stops and re-syncs the authoritative final state.
      onMapIdle={handleCameraChanged}
      onPress={(feature) => {
        if (Date.now() - markerTouchAt.current < 700) return;  // the tap was a marker's
        if (fan) { setFan(null); return; }                      // a tap closes the fan, nothing else
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
              ? { lineColor: colors.mapAction, lineWidth: 3.5, lineOpacity: 0.9, lineJoin: 'round', lineCap: 'round' }
              : { lineColor: '#FFFFFF', lineWidth: 2, lineDasharray: [4, 3], lineOpacity: 0.7 }}
          />
        </Mapbox.ShapeSource>
      )}

      {/* Inline label icons (registered once): calendar (when / schedule) and
          the level bars. The rating ★ is a text character, not an image. */}
      <Mapbox.Images
        images={{
          // Size set by `scale` (font-scale is ignored for inline images
          // natively): scale 2.3 ≈ the secondary-text height.
          cal: { image: require('../../assets/label-cal.png'), scale: 4.6 },
          'star-full': { image: require('../../assets/label-star-full.png'), scale: 4.2 },
          'star-empty': { image: require('../../assets/label-star-empty.png'), scale: 4.2 },
          lvl: { image: require('../../assets/label-level.png'), scale: 2.3 },
          // Monochrome teardrop mask (SDF) — tinted per-pin via iconColor in
          // the pinsAsLayers path.
          'drop-pin': { image: require('../../assets/drop-pin-mask.png'), sdf: true },
        }}
      />

      {/* On-map labels — colored text + white halo, native collision +
          zoom-stepping (names at NAME zoom, +detail at DETAIL zoom). Rides
          the declustered points; sits under the MarkerView pins. */}
      <Mapbox.ShapeSource
        id="pin-labels"
        shape={labelShape}
        // The labels are native symbols, not React views: the pin's Pressable
        // never covers them, so tapping a title did nothing (Scott 2026-10-05).
        // Route a label hit to the same handler as its pin.
        onPress={(e) => {
          const props = e.features[0]?.properties as { kind?: string; id?: string } | undefined;
          if (!props?.id) return;
          if (props.kind === 'activity') {
            const activity = activityMap.get(props.id);
            if (activity) onActivityPress?.(activity);
          } else if (props.kind === 'pro') {
            const pro = proMap.get(props.id);
            if (pro) onProPress?.(pro);
          } else if (props.kind === 'offering') {
            const offering = offeringMap.get(props.id);
            if (offering) onProOfferingPress?.(offering);
          }
        }}
      >
        <Mapbox.SymbolLayer
          id="pin-labels-layer"
          minZoomLevel={LABEL_NAME_ZOOM}
          style={{
            textField: [
              'step', ['zoom'],
              // Below DETAIL: title + the star line — the trust signal shows
              // as soon as names do (Scott 2026-09-29).
              ['format',
                ['get', 'name'], { 'text-color': ['get', 'color'] },
                ['case', ['>', ['length', ['get', 'rtext']], 0], '\n', ''], {},
                ['case', ['>', ['length', ['get', 'rtext']], 0], ['image', ['get', 's1']], ''], IMG,
                ['case', ['>', ['length', ['get', 'rtext']], 0], ['image', ['get', 's2']], ''], IMG,
                ['case', ['>', ['length', ['get', 'rtext']], 0], ['image', ['get', 's3']], ''], IMG,
                ['case', ['>', ['length', ['get', 'rtext']], 0], ['image', ['get', 's4']], ''], IMG,
                ['case', ['>', ['length', ['get', 'rtext']], 0], ['image', ['get', 's5']], ''], IMG,
                ['get', 'rtext'], SEC,
              ],
              LABEL_DETAIL_ZOOM,
              // At DETAIL: title (colour) / ★rating on its own line / details
              // line = [📅 when][📊 level] or [📅 schedule] or [tagline].
              // Empty sections collapse.
              ['format',
                ['get', 'name'], { 'text-color': ['get', 'color'] },
                // the star line DIRECTLY under the title (Scott 2026-09-29)
                ['case', ['>', ['length', ['get', 'rtext']], 0], '\n', ''], {},
                ['case', ['>', ['length', ['get', 'rtext']], 0], ['image', ['get', 's1']], ''], IMG,
                ['case', ['>', ['length', ['get', 'rtext']], 0], ['image', ['get', 's2']], ''], IMG,
                ['case', ['>', ['length', ['get', 'rtext']], 0], ['image', ['get', 's3']], ''], IMG,
                ['case', ['>', ['length', ['get', 'rtext']], 0], ['image', ['get', 's4']], ''], IMG,
                ['case', ['>', ['length', ['get', 'rtext']], 0], ['image', ['get', 's5']], ''], IMG,
                ['get', 'rtext'], SEC,
                '\n', {},
                // then: 📅 when / schedule (RA may wrap; UA when stays short)
                ['match', ['get', 'd2icon'], 'cal', ['image', 'cal'], ''], IMG,
                ['case', ['>', ['length', ['get', 'd2icon']], 0], ' ', ''], SEC,
                ['get', 'd2'], SEC,
                // level signal on its own line (UA only)
                ['case', ['>', ['length', ['get', 'lvl']], 0], '\n', ''], SEC,
                ['match', ['get', 'lvlicon'], 'lvl', ['image', 'lvl'], ''], IMG,
                ['case', ['>', ['length', ['get', 'lvlicon']], 0], ' ', ''], SEC,
                ['get', 'lvl'], SEC,
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
            // Wide enough that the UA date+time never wraps; long RA schedules
            // still wrap past this.
            textMaxWidth: 13,
            textAllowOverlap: false,
            textOptional: true,
            symbolSortKey: ['match', ['get', 'kind'], 'pro', 0, 'offering', 1, 2],
          }}
        />
      </Mapbox.ShapeSource>

      {userLocation && (
        <Mapbox.MarkerView id="user-location" coordinate={userLocation} allowOverlap>
          <UserLocationDot />
        </Mapbox.MarkerView>
      )}

      {tapMarker && (
        <Mapbox.MarkerView id="tap-marker" coordinate={tapMarker} anchor={{ x: 0.5, y: 0 }} allowOverlap>
          <View>{tapMarkerContent ?? <AppText style={styles.tapMarker}>✕</AppText>}</View>
        </Mapbox.MarkerView>
      )}

      {/* pinsAsLayers: pure GL rendering (dot + white ring) — MarkerViews can
          silently fail to attach on secondary map instances (modals); GL
          layers ride the tile pipeline and always draw. No tap handling. */}
      {pinsAsLayers && pins.length > 0 ? (
        <Mapbox.ShapeSource
          id="static-pins-src"
          shape={{
            type: 'FeatureCollection',
            features: pins.map((pin) => ({
              type: 'Feature' as const,
              geometry: { type: 'Point' as const, coordinates: pin.coordinate },
              properties: { color: pin.color },
            })),
          }}
        >
          {/* GL replica of MapPinIcon at its exact display size (16×22 =
              iconSize 0.25 of the 64×88 mask): dark offset copy as the drop
              shadow, tinted teardrop, white head highlight (head center sits
              15px above the tip at this scale). */}
          <Mapbox.SymbolLayer
            id="static-pins-shadow"
            style={{
              iconImage: 'drop-pin',
              iconColor: 'rgba(10,15,26,0.35)',
              iconAnchor: 'bottom',
              iconSize: 0.27,
              iconTranslate: [1, 2],
              iconTranslateAnchor: 'viewport',
              iconAllowOverlap: true,
              iconIgnorePlacement: true,
            }}
          />
          <Mapbox.SymbolLayer
            id="static-pins-drop"
            style={{
              iconImage: 'drop-pin',
              iconColor: ['get', 'color'],
              iconAnchor: 'bottom',
              iconSize: 0.25,
              iconAllowOverlap: true,
              iconIgnorePlacement: true,
            }}
          />
          <Mapbox.CircleLayer
            id="static-pins-highlight"
            style={{
              circleRadius: 2.5,
              circleColor: 'rgba(255,255,255,0.85)',
              circleTranslate: [0, -14],
              circleTranslateAnchor: 'viewport',
              circlePitchAlignment: 'map',
            }}
          />
        </Mapbox.ShapeSource>
      ) : (
        pins.map((pin) => (
          <Mapbox.MarkerView key={pin.id} id={pin.id} coordinate={pin.coordinate} anchor={MAP_PIN_ANCHOR} allowOverlap>
            <Pressable onPressIn={stampMarkerTouch} onPress={() => onPinPress?.(pin)} hitSlop={10}>
              <MapPinIcon color={pin.color} />
            </Pressable>
          </Mapbox.MarkerView>
        ))
      )}

      {/* Unified render loop. Mixes activity, pro storefront, and pro
          offering pins. Cluster pins show total count regardless of
          type; tap zooms to expansion so typed individual pins emerge. */}
      {[...clusters]
        .sort((a, b) => {
          // Draw order (last = on top): plain pins, then clusters — a nearby
          // pin's enlarged hit area must not catch a tap meant for a cluster
          // (Scott 2026-10-22) — then the selected activity, so its popup
          // stays above everything.
          const rank = (f: typeof a) => {
            const pr = f.properties as PinPointProps | (Supercluster.ClusterProperties & PinPointProps);
            if ('cluster' in pr && pr.cluster) return 1;
            if ('type' in pr && pr.type === 'activity' && pr.id === selectedActivity?.id) return 2;
            return 0;
          };
          return rank(a) - rank(b);
        })
        .map((feature) => {
        const lng = feature.geometry.coordinates[0] ?? 0;
        const lat = feature.geometry.coordinates[1] ?? 0;
        const props = feature.properties;

        if ('cluster' in props && props.cluster) {
          const clusterId = (props.cluster_id ?? 0) as number;
          const count = (props.point_count ?? 0) as number;
          const aggProps = props as unknown as Partial<ClusterAgg>;
          const agg = aggProps.u ?? {};
          const stableKey = aggProps.k ?? String(clusterId);
          if (fan?.key === stableKey) return null; // open as a fan below
          const segments: ClusterSegment[] = UNIVERSE_ORDER
            .filter((k) => (agg[k] ?? 0) > 0)
            .map((k) => ({ color: SPORT_CATEGORY_COLORS[k] ?? colors.cta, count: agg[k] ?? 0 }));

          return (
            <Mapbox.MarkerView
              key={`cluster-${stableKey}`}
              id={`cluster-${stableKey}`}
              coordinate={[lng, lat]}
              allowOverlap
            >
              <Pressable onPressIn={stampMarkerTouch} onPress={() => {
                const leaves = cluster.getLeaves(clusterId, Infinity);
                // Bounding box of every point under this cluster + track the
                // southernmost leaf (lowest latitude = lowest on screen).
                let minLng = Infinity, minLat = Infinity, maxLng = -Infinity, maxLat = -Infinity;
                let lowestLng = lng, lowestLat = lat;
                for (const leaf of leaves) {
                  const llng = leaf.geometry.coordinates[0] ?? 0;
                  const llat = leaf.geometry.coordinates[1] ?? 0;
                  if (llng < minLng) minLng = llng;
                  if (llng > maxLng) maxLng = llng;
                  if (llat < minLat) { minLat = llat; lowestLng = llng; lowestLat = llat; }
                  if (llat > maxLat) maxLat = llat;
                }
                // ~3e-5° ≈ 3m, below the pin footprint even at max zoom: these
                // points can never visually separate, so hand the leaf
                // ACTIVITIES to the drawer instead (pros/offerings cluster fine
                // via spatial proximity and aren't surfaced here yet).
                const separable = Number.isFinite(minLng) && (maxLng - minLng > 3e-5 || maxLat - minLat > 3e-5);
                if (!separable) {
                  // Same spot: recentre on it — and zoom in first when the map is
                  // wide, so the fan doesn't land among other pins (Scott
                  // 2026-10-27) — then open the fan (halo) at the target zoom.
                  cameraTouched.current = true;
                  const targetZoom = Math.max(currentZoom, FAN_MIN_ZOOM);
                  cameraRef.current?.setCamera({ centerCoordinate: [lng, lat], zoomLevel: targetZoom, animationDuration: targetZoom > currentZoom + 0.05 ? 450 : 250 });
                  const { leaves: fl, radiusPx } = fanLeaves(leaves as PinPoint[], [lng, lat], targetZoom);
                  setFan({ key: stableKey, center: [lng, lat], zoom: targetZoom, radiusPx, leaves: fl, openedAt: Date.now() });
                  return;
                }
                cameraTouched.current = true;
                if (separable) {
                  // Center on the southernmost pin (lowest on screen) and zoom
                  // just enough to break the cluster apart — the other pins
                  // surface right above it. (Scott's preference over framing the
                  // midpoint; a large cluster may leave a sub-group to re-tap.)
                  const expansionZoom = cluster.getClusterExpansionZoom(clusterId);
                  cameraRef.current?.setCamera({
                    centerCoordinate: [lowestLng, lowestLat],
                    zoomLevel: expansionZoom,
                    animationDuration: 400,
                  });
                } else {
                  cameraRef.current?.setCamera({ centerCoordinate: [lng, lat], zoomLevel: 18, animationDuration: 300 });
                }
              }}>
                <ClusterPin count={count} segments={segments} />
              </Pressable>
            </Mapbox.MarkerView>
          );
        }

        // Individual pin — branch on type for shape + tap handler.
        const pinProps = props as PinPointProps;
        return pinMarker(pinProps, lng, lat);
      })}

      {/* The fan: halo under, then the spread pins, drawn after every other
          marker so they sit on top. Tapping one closes the fan first. */}
      {fan && (
        <Mapbox.MarkerView key={`fan-halo-${fan.key}`} id={`fan-halo-${fan.key}`} coordinate={fan.center} anchor={{ x: 0.5, y: 0.5 }} allowOverlap>
          <View pointerEvents="none" style={[styles.fanHalo, { width: 2 * (fan.radiusPx + FAN_HALO_PAD), height: 2 * (fan.radiusPx + FAN_HALO_PAD), borderRadius: fan.radiusPx + FAN_HALO_PAD }]}>
            <View style={styles.fanCentre}><View style={styles.fanDot} /></View>
          </View>
        </Mapbox.MarkerView>
      )}
      {fan?.leaves.map((leaf) => pinMarker(leaf.props, leaf.lng, leaf.lat, '-fan', () => setFan(null), leaf.lng < fan.center[0] - 1e-9 ? 'left' : 'right'))}

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
    </Mapbox.MapView>
  );

  const attribution = MAP_STYLE_ATTRIBUTIONS[mapStyleKey];
  if (attribution) {
    return (
      <View style={styles.mapWrapper}>
        {mapView}
        <View style={styles.attributionPill} pointerEvents="none">
          <AppText style={styles.attributionText}>{attribution}</AppText>
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
  // The fan's ground: a translucent white disc, softly shadowed; the centre
  // marks the real spot (ring + dot).
  // No shadow / elevation: Android draws it through a translucent disc and it
  // read as a dark polygon under the white (Scott 2026-10-27).
  fanHalo: {
    backgroundColor: 'rgba(255,255,255,0.78)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  fanLabel: { position: 'absolute', top: 2, width: 150 },
  fanLabelRight: { left: 50 },
  fanLabelLeft: { right: 50 },
  fanLabelName: { fontSize: 12, fontWeight: '800', lineHeight: 14, textShadowColor: '#FFFFFF', textShadowRadius: 4 },
  fanLabelRow: { flexDirection: 'row', alignItems: 'center', gap: 3 },
  fanLabelRowLeft: { justifyContent: 'flex-end' },
  fanLabelSub: { fontSize: 10.5, fontWeight: '600', color: colors.textSecondary, lineHeight: 13, textShadowColor: '#FFFFFF', textShadowRadius: 4, flexShrink: 1 },
  fanCentre: {
    width: 14, height: 14, borderRadius: 7, backgroundColor: colors.pinBackground,
    borderWidth: 1.5, borderColor: colors.pinBorder, alignItems: 'center', justifyContent: 'center',
  },
  fanDot: { width: 5, height: 5, borderRadius: 2.5, backgroundColor: colors.pinBorder },
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
});
