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
