import { supabase } from './supabase';
import type { GeoJsonLineString } from './activity-service';

export type SnapResult =
  | { ok: true; coordinates: [number, number][] }
  | { ok: false };

// Snap a single segment (2 waypoints) onto the nearest real trail via the
// `snap-trail` edge function (OpenRouteService foot-hiking). Returns the routed
// coordinates, or ok:false when the point is off-trail / snap is unavailable —
// the caller then keeps a straight segment. Never throws.
export const snapTrailService = {
  snapSegment: async (
    a: [number, number],
    b: [number, number],
  ): Promise<SnapResult> => {
    try {
      const { data, error } = await supabase.functions.invoke('snap-trail', {
        body: { coordinates: [a, b] },
      });
      if (error) return { ok: false };
      const d = data as { ok?: boolean; geometry?: GeoJsonLineString } | null;
      if (d?.ok && d.geometry?.coordinates && d.geometry.coordinates.length >= 2) {
        return { ok: true, coordinates: d.geometry.coordinates as [number, number][] };
      }
      return { ok: false };
    } catch {
      return { ok: false };
    }
  },
};
