// Approximate area from the IP address, used only when the GPS position is not
// available (permission refused, no fix). HTTPS on purpose: a release Android
// build refuses clear-text calls, so the former http:// service failed silently
// and everyone without GPS landed on the same fallback.
interface GeoJsResponse {
  latitude?: string;
  longitude?: string;
}

export const geolocationService = {
  getIpCenter: async (): Promise<[number, number] | null> => {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 5000);
    try {
      const response = await fetch('https://get.geojs.io/v1/ip/geo.json', { signal: controller.signal });
      if (!response.ok) return null;
      const data: GeoJsResponse = await response.json();
      const lat = Number(data.latitude);
      const lng = Number(data.longitude);
      if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;
      return [lng, lat];
    } catch {
      return null;
    } finally {
      clearTimeout(timer);
    }
  },
};
