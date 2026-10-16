import { supabase } from '@/services/supabase';
import type { GeoJsonLineString } from '@/services/activity-service';

// Altitudes on a trace (Scott 2026-10-16). A GPX imported from Strava /
// Komoot / Garmin carries them as the third coordinate (parse-gpx keeps
// <ele>); a trace drawn in-app does not. Before a trace is stored, give it
// altitudes from the IGN altimetry service through the `trace-elevation` edge
// function, so the server can derive the elevation gain in SQL for every
// trace alike (mig 00452). Best effort: on any failure (offline, quota,
// outside France) the trace is kept as it is and D+ simply stays empty.

// Same rule as trace_elevation_gain_m: a trace "has" altitudes when ≥ 90 %
// of its points carry a finite third coordinate.
export function traceHasElevation(geo: GeoJsonLineString): boolean {
  const n = geo.coordinates.length;
  if (n === 0) return false;
  let withZ = 0;
  for (const c of geo.coordinates) {
    const z = c[2];
    if (typeof z === 'number' && Number.isFinite(z)) withZ += 1;
  }
  return withZ >= Math.ceil(n * 0.9);
}

export async function enrichTraceElevation(geo: GeoJsonLineString): Promise<GeoJsonLineString> {
  if (traceHasElevation(geo)) return geo;
  try {
    const coordinates = geo.coordinates.map((c) => [c[0], c[1]]);
    const { data, error } = await supabase.functions.invoke('trace-elevation', {
      body: { coordinates },
    });
    if (error) return geo;
    const d = data as { ok?: boolean; z?: (number | null)[] } | null;
    if (!d?.ok || !Array.isArray(d.z) || d.z.length !== geo.coordinates.length) return geo;
    const z = d.z;
    return {
      type: 'LineString',
      coordinates: geo.coordinates.map((c, i) => {
        const alt = z[i];
        return typeof alt === 'number' ? [c[0]!, c[1]!, alt] : [c[0]!, c[1]!];
      }),
    };
  } catch {
    return geo;
  }
}
