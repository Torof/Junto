import { House, Tent, Droplet, Binoculars, Sandwich, SquareParking, MountainSnow, TriangleAlert, MapPin } from 'lucide-react-native';
import type { LucideIcon } from 'lucide-react-native';
import type { GeoJsonLineString, TraceWaypoint, TraceWaypointKind } from '@/services/activity-service';

// Waypoints on a trace (Scott 2026-11-02, option 2): placed after the trace
// exists — drawn or imported — by tapping on it; the point snaps onto the line.
// Same list as the DB gate (trace_geojson_ok, mig 00570).

export const MAX_WAYPOINTS = 30;
export const WAYPOINT_NAME_MAX = 60;

export const WAYPOINT_KINDS: { kind: TraceWaypointKind; Icon: LucideIcon }[] = [
  { kind: 'refuge', Icon: House },
  { kind: 'camp', Icon: Tent },
  { kind: 'water', Icon: Droplet },
  { kind: 'viewpoint', Icon: Binoculars },
  { kind: 'food', Icon: Sandwich },
  { kind: 'parking', Icon: SquareParking },
  { kind: 'summit', Icon: MountainSnow },
  { kind: 'danger', Icon: TriangleAlert },
  { kind: 'other', Icon: MapPin },
];

export const waypointIcon = (kind: TraceWaypointKind): LucideIcon =>
  WAYPOINT_KINDS.find((k) => k.kind === kind)?.Icon ?? MapPin;

// The DB refuses < > and control characters in a name: strip them here.
export const cleanWaypointName = (s: string): string | undefined => {
  const v = s.replace(/[<>\u0000-\u001f\u007f]/g, '').trim().slice(0, WAYPOINT_NAME_MAX);
  return v || undefined;
};

// Nearest point ON the polyline (segment projection in a local equirectangular
// frame — exact enough at trace scale).
export function snapToLine(lng: number, lat: number, coords: number[][]): { lng: number; lat: number } {
  const k = Math.cos((lat * Math.PI) / 180);
  let best = { lng, lat };
  let bestD = Infinity;
  for (let i = 0; i < coords.length - 1; i++) {
    const a = coords[i]!;
    const b = coords[i + 1]!;
    const ax = a[0]! * k, ay = a[1]!, bx = b[0]! * k, by = b[1]!;
    const px = lng * k, py = lat;
    const dx = bx - ax, dy = by - ay;
    const len2 = dx * dx + dy * dy;
    const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2));
    const qx = ax + t * dx, qy = ay + t * dy;
    const d = (px - qx) ** 2 + (py - qy) ** 2;
    if (d < bestD) { bestD = d; best = { lng: qx / k, lat: qy }; }
  }
  return best;
}

// Distance along the trace to a point, used to list waypoints in route order.
export function positionAlong(lng: number, lat: number, coords: number[][]): number {
  const k = Math.cos((lat * Math.PI) / 180);
  let walked = 0;
  let best = 0;
  let bestD = Infinity;
  for (let i = 0; i < coords.length - 1; i++) {
    const a = coords[i]!;
    const b = coords[i + 1]!;
    const ax = a[0]! * k, ay = a[1]!, dx = b[0]! * k - ax, dy = b[1]! - ay;
    const len = Math.hypot(dx, dy);
    const t = len === 0 ? 0 : Math.max(0, Math.min(1, ((lng * k - ax) * dx + (lat - ay) * dy) / (len * len)));
    const d = (lng * k - (ax + t * dx)) ** 2 + (lat - (ay + t * dy)) ** 2;
    if (d < bestD) { bestD = d; best = walked + t * len; }
    walked += len;
  }
  return best;
}

export const sortAlongTrace = (wps: TraceWaypoint[], coords: number[][]): TraceWaypoint[] =>
  [...wps].sort((a, b) => positionAlong(a.lng, a.lat, coords) - positionAlong(b.lng, b.lat, coords));

// Same trace with its waypoints replaced (empty list → member dropped).
export const withWaypoints = (geo: GeoJsonLineString, wps: TraceWaypoint[]): GeoJsonLineString => {
  const { waypoints: _old, ...line } = geo;
  return wps.length > 0 ? { ...line, waypoints: sortAlongTrace(wps, geo.coordinates).slice(0, MAX_WAYPOINTS) } : line;
};

// GPX <wpt> → kind, from its <type>, <sym> or <name> (Garmin / Komoot /
// OsmAnd vocabularies, FR + EN keywords). Unknown → 'other'.
const KIND_WORDS: [TraceWaypointKind, RegExp][] = [
  ['refuge', /refuge|hut|cabane|chalet|lodge|gîte|gite|lodging|house|hotel/i],
  ['camp', /bivouac|bivy|camp|tent|tente/i],
  ['water', /water|eau|source|fontaine|spring|drinking/i],
  ['viewpoint', /view|vue|panorama|belvéd|belved|scenic|overlook/i],
  ['food', /food|picnic|pique|restaurant|snack|sandwich|meal|repas/i],
  ['parking', /parking|car park|trailhead|parc auto/i],
  ['summit', /summit|sommet|peak|pic\b|mountain|col\b|pass\b/i],
  ['danger', /danger|caution|warning|attention|delicate|délicat|exposed|exposé/i],
];
// Words are tried in order (type, then symbol, then name): the first one
// that says something wins.
export function kindFromGpx(...words: (string | undefined)[]): TraceWaypointKind {
  for (const w of words) {
    if (!w) continue;
    for (const [kind, re] of KIND_WORDS) if (re.test(w)) return kind;
  }
  return 'other';
}
