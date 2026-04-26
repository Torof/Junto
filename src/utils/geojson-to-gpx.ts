import type { GeoJsonLineString } from '@/services/activity-service';

const escapeXml = (s: string) =>
  s.replace(/&/g, '&amp;')
   .replace(/</g, '&lt;')
   .replace(/>/g, '&gt;')
   .replace(/"/g, '&quot;')
   .replace(/'/g, '&apos;');

export function geoJsonLineStringToGpx(geo: GeoJsonLineString, name: string): string {
  const safeName = escapeXml(name);
  const points = geo.coordinates
    .map((c) => {
      const lng = c[0];
      const lat = c[1];
      const ele = c[2];
      if (lng === undefined || lat === undefined) return '';
      const eleTag = ele !== undefined ? `<ele>${ele}</ele>` : '';
      return `      <trkpt lat="${lat}" lon="${lng}">${eleTag}</trkpt>`;
    })
    .filter(Boolean)
    .join('\n');
  return `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Junto" xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <name>${safeName}</name>
    <trkseg>
${points}
    </trkseg>
  </trk>
</gpx>
`;
}
