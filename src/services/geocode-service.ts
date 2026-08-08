// Place search via Photon (Komoot, OpenStreetMap-based) — free, autocomplete-
// first, covers outdoor places (summits, lakes, trailheads) + towns, unlike an
// address-only geocoder. Public API is fair-use; self-host if we scale.
// Decision 2026-08-04: Photon for map place-search (see project_friction_features).

export interface PlaceResult {
  id: string;
  label: string;
  sublabel: string;
  lng: number;
  lat: number;
}

interface PhotonFeature {
  geometry?: { coordinates?: [number, number] };
  properties?: {
    osm_id?: number;
    name?: string;
    city?: string;
    state?: string;
    country?: string;
    county?: string;
  };
}

export const geocodeService = {
  // `bias` (current map center) ranks nearby results first. `signal` lets the
  // caller cancel an in-flight request when the query changes.
  searchPlaces: async (
    query: string,
    bias?: { lat: number; lng: number },
    signal?: AbortSignal,
  ): Promise<PlaceResult[]> => {
    const q = query.trim();
    if (q.length < 2) return [];
    const params = new URLSearchParams({ q, limit: '6', lang: 'fr' });
    if (bias) {
      params.set('lat', String(bias.lat));
      params.set('lon', String(bias.lng));
    }
    const res = await fetch(`https://photon.komoot.io/api/?${params.toString()}`, { signal });
    if (!res.ok) throw new Error(`geocode ${res.status}`);
    const json = (await res.json()) as { features?: PhotonFeature[] };
    return (json.features ?? [])
      .map((f, i): PlaceResult | null => {
        const coords = f.geometry?.coordinates;
        const p = f.properties ?? {};
        if (!coords || typeof coords[0] !== 'number' || typeof coords[1] !== 'number') return null;
        const label = p.name ?? p.city ?? '?';
        const sublabel = [p.city, p.county, p.state, p.country]
          .filter((x): x is string => !!x && x !== label)
          .join(', ');
        return { id: `${p.osm_id ?? 'x'}-${i}`, label, sublabel, lng: coords[0], lat: coords[1] };
      })
      .filter((r): r is PlaceResult => r !== null);
  },
};
