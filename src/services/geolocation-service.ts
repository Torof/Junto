// Default center: Briançon, France (founding use case)
const DEFAULT_CENTER: [number, number] = [6.6323, 44.8967];

interface IpLocationResponse {
  lat: number;
  lon: number;
  status: string;
}

export const geolocationService = {
  getInitialCenter: async (): Promise<[number, number]> => {
    try {
      const response = await fetch('http://ip-api.com/json/?fields=status,lat,lon');
      const data: IpLocationResponse = await response.json();
      if (data.status === 'success') {
        return [data.lon, data.lat];
      }
      return DEFAULT_CENTER;
    } catch {
      return DEFAULT_CENTER;
    }
  },
};
