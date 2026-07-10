/**
 * Great-circle distance between two points in meters (haversine formula).
 *
 * Sufficient for the proximity checks we run on-device — geofence radius
 * comparisons, "is the user within 150m of an activity" — where the small
 * earth-as-a-sphere error is well below GPS noise. PostGIS should be used
 * server-side for anything that crosses the wire.
 */
export function distanceMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371000;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/**
 * Minimum distance in meters from a point to a GeoJSON LineString
 * (coordinates in [lng, lat] order). Projects everything to a local
 * equirectangular plane centered on the point, then takes the min
 * point-to-segment distance — the flat-earth error is negligible at the
 * 150m scale this is used for. Mirrors the server-side
 * ST_Distance(trace, point) term in confirm_presence_via_geo.
 */
export function distanceToPolylineMeters(lat: number, lng: number, line: number[][]): number {
  const R = 6371000;
  const toRad = Math.PI / 180;
  const cosLat = Math.cos(lat * toRad);
  let min = Infinity;
  let prevX = 0;
  let prevY = 0;
  let hasPrev = false;
  for (const c of line) {
    const cx = c[0];
    const cy = c[1];
    // Also rejects NaN — one bad vertex would otherwise poison the whole
    // min into NaN and permanently report "not in the zone".
    if (cx == null || cy == null || !Number.isFinite(cx) || !Number.isFinite(cy)) continue;
    const x = (cx - lng) * toRad * cosLat * R;
    const y = (cy - lat) * toRad * R;
    if (hasPrev) {
      const dx = x - prevX;
      const dy = y - prevY;
      const lenSq = dx * dx + dy * dy;
      const t = lenSq === 0 ? 0 : Math.max(0, Math.min(1, -(prevX * dx + prevY * dy) / lenSq));
      min = Math.min(min, Math.hypot(prevX + t * dx, prevY + t * dy));
    } else {
      min = Math.min(min, Math.hypot(x, y));
    }
    prevX = x;
    prevY = y;
    hasPrev = true;
  }
  return min;
}

/**
 * Build a closed-ring polygon approximating a geodesic circle around a
 * (lng, lat) center, with the given radius in km. Used to draw the radius
 * filter overlay on the map. 64 vertices is enough that the eye reads it
 * as a smooth circle at any reasonable zoom.
 */
export function circlePolygon(
  centerLng: number,
  centerLat: number,
  radiusKm: number,
  steps = 64,
): [number, number][] {
  const earthRadius = 6371; // km
  const coords: [number, number][] = [];
  const cosLat = Math.cos((centerLat * Math.PI) / 180);
  for (let i = 0; i <= steps; i++) {
    const angle = (i / steps) * 2 * Math.PI;
    const dxKm = radiusKm * Math.cos(angle);
    const dyKm = radiusKm * Math.sin(angle);
    const lat = centerLat + (dyKm / earthRadius) * (180 / Math.PI);
    const lng = centerLng + ((dxKm / earthRadius) * (180 / Math.PI)) / cosLat;
    coords.push([lng, lat]);
  }
  return coords;
}
