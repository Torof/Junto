// Parse PostGIS geography point to [lng, lat] coordinate
// Supabase returns geography as GeoJSON string or object
export function parsePoint(location: unknown): [number, number] | null {
  if (!location) return null;

  try {
    // If it's a string, parse it
    const geo = typeof location === 'string' ? JSON.parse(location) : location;

    if (geo && geo.type === 'Point' && Array.isArray(geo.coordinates)) {
      const [lng, lat] = geo.coordinates as [number, number];
      return [lng, lat];
    }

    return null;
  } catch {
    return null;
  }
}
