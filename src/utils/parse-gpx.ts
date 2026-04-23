import type { GeoJsonLineString } from '@/services/activity-service';

export class GpxParseError extends Error {}

const MAX_POINTS = 10000;

/**
 * Minimal GPX → GeoJSON LineString parser.
 *
 * Extracts track points (`<trkpt>`) by default; falls back to route points
 * (`<rtept>`) if no track is found. Waypoints (`<wpt>`) are intentionally
 * ignored — they describe pins, not a continuous path.
 *
 * Regex-based on purpose: React Native has no built-in XML parser and
 * pulling a full DOM implementation is overkill. Well-formed GPX from
 * Garmin / Strava / Gaia / Komoot / open-gpx.com parses cleanly; truly
 * malformed XML throws a `GpxParseError`.
 */
export function parseGpxToGeoJson(xml: string): GeoJsonLineString {
  if (!xml || xml.length === 0) {
    throw new GpxParseError('Empty file');
  }

  const trkptRegex = /<trkpt\b([^>]*?)(?:\/>|>([\s\S]*?)<\/trkpt>)/gi;
  const rteptRegex = /<rtept\b([^>]*?)(?:\/>|>([\s\S]*?)<\/rtept>)/gi;

  const extract = (regex: RegExp): number[][] => {
    const points: number[][] = [];
    let match: RegExpExecArray | null;
    while ((match = regex.exec(xml)) !== null) {
      const attrs = match[1] ?? '';
      const body = match[2] ?? '';
      const latMatch = attrs.match(/\blat\s*=\s*['"]([-\d.]+)['"]/i);
      const lonMatch = attrs.match(/\blon\s*=\s*['"]([-\d.]+)['"]/i);
      if (!latMatch || !lonMatch) continue;
      const lat = parseFloat(latMatch[1]!);
      const lon = parseFloat(lonMatch[1]!);
      if (!Number.isFinite(lat) || !Number.isFinite(lon)) continue;
      if (lat < -90 || lat > 90 || lon < -180 || lon > 180) continue;

      const eleMatch = body.match(/<ele>\s*([-\d.]+)\s*<\/ele>/i);
      const point: number[] = [lon, lat];
      if (eleMatch) {
        const ele = parseFloat(eleMatch[1]!);
        if (Number.isFinite(ele)) point.push(ele);
      }
      points.push(point);
      if (points.length > MAX_POINTS) break;
    }
    return points;
  };

  let coords = extract(trkptRegex);
  if (coords.length === 0) {
    coords = extract(rteptRegex);
  }

  if (coords.length < 2) {
    throw new GpxParseError('No track or route points found');
  }

  if (coords.length > MAX_POINTS) {
    throw new GpxParseError(`Too many points (${coords.length} > ${MAX_POINTS})`);
  }

  return { type: 'LineString', coordinates: coords };
}
