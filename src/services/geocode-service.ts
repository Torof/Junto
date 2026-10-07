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
    osm_key?: string;
    osm_value?: string;
    name?: string;
    city?: string;
    district?: string;
    locality?: string;
    state?: string;
    country?: string;
    county?: string;
  };
}

// OSM place values that name an inhabited place — the granularity we want for
// a rendez-vous (« Puy-Chalvin », not « Parking de la ferme », not « Hautes-Alpes »).
const SETTLEMENT_VALUES = new Set(['city', 'town', 'village', 'hamlet', 'locality', 'suburb', 'neighbourhood', 'isolated_dwelling']);

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

  // Reverse geocode a point (Photon /reverse) → the nearest named place. Used to
  // label a departure the user placed by hand on the map. Returns null if
  // nothing usable is found (caller falls back to a generic label).
  reverse: async (lat: number, lng: number, signal?: AbortSignal): Promise<string | null> => {
    const params = new URLSearchParams({ lat: String(lat), lon: String(lng), lang: 'fr' });
    const res = await fetch(`https://photon.komoot.io/reverse?${params.toString()}`, { signal });
    if (!res.ok) throw new Error(`reverse ${res.status}`);
    const json = (await res.json()) as { features?: PhotonFeature[] };
    const p = (json.features ?? [])[0]?.properties;
    if (!p) return null;
    const label = p.name ?? p.city ?? p.county ?? null;
    if (!label) return null;
    const extra = [p.city, p.county].find((x) => !!x && x !== label);
    return extra ? `${label}, ${extra}` : label;
  },

  // The village / hamlet / commune a point falls in (mig 00441,
  // activities.meeting_locality). Unlike `reverse`, never a POI or a street:
  // the nearest feature's own name only when it IS a settlement, else the
  // locality/district/city Photon attaches to it. Null when nothing usable —
  // the caller must never block on this.
  reverseLocality: async (lat: number, lng: number, signal?: AbortSignal): Promise<string | null> => {
    const params = new URLSearchParams({ lat: String(lat), lon: String(lng), lang: 'fr', limit: '3' });
    const res = await fetch(`https://photon.komoot.io/reverse?${params.toString()}`, { signal });
    if (!res.ok) throw new Error(`reverse ${res.status}`);
    const json = (await res.json()) as { features?: PhotonFeature[] };
    for (const f of json.features ?? []) {
      const p = f.properties ?? {};
      if (p.osm_key === 'place' && p.osm_value && SETTLEMENT_VALUES.has(p.osm_value) && p.name) {
        return p.name.slice(0, 80);
      }
    }
    const p = (json.features ?? [])[0]?.properties ?? {};
    const label = p.locality ?? p.district ?? p.city ?? p.county ?? null;
    return label ? label.slice(0, 80) : null;
  },
};
