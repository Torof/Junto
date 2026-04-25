import { create } from 'zustand';
import AsyncStorage from '@react-native-async-storage/async-storage';

export type MapStyleKey =
  | 'outdoors'
  | 'streets'
  | 'satellite'
  | 'satellite-streets'
  | 'light'
  | 'dark'
  | 'opentopomap'
  | 'ign-plan'
  | 'ign-ortho';

export const MAP_STYLE_URLS: Partial<Record<MapStyleKey, string>> = {
  outdoors: 'mapbox://styles/mapbox/outdoors-v12',
  streets: 'mapbox://styles/mapbox/streets-v12',
  satellite: 'mapbox://styles/mapbox/satellite-v9',
  'satellite-streets': 'mapbox://styles/mapbox/satellite-streets-v12',
  light: 'mapbox://styles/mapbox/light-v11',
  dark: 'mapbox://styles/mapbox/dark-v11',
};

// IGN Géoplateforme WMTS URL — tiles publiques Etalab, sans clé API.
// PNG pour les plans, JPEG pour les orthos (contrainte IGN).
const ignWmts = (layer: string, format: 'png' | 'jpeg' = 'png') =>
  `https://data.geopf.fr/wmts?SERVICE=WMTS&VERSION=1.0.0&REQUEST=GetTile&LAYER=${layer}&STYLE=normal&TILEMATRIXSET=PM&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image%2F${format}`;

const rasterStyleJson = (sourceId: string, tileUrl: string, maxzoom: number, bgColor: string, attribution: string) =>
  JSON.stringify({
    version: 8,
    sources: {
      [sourceId]: {
        type: 'raster',
        tiles: [tileUrl],
        tileSize: 256,
        maxzoom,
        attribution,
      },
    },
    layers: [
      { id: `${sourceId}-bg`, type: 'background', paint: { 'background-color': bgColor } },
      { id: `${sourceId}-tiles`, type: 'raster', source: sourceId },
    ],
  });

// Inline style JSONs for non-Mapbox raster providers.
// Uses Mapbox GL style spec v8 with a raster source.
export const MAP_STYLE_JSONS: Partial<Record<MapStyleKey, string>> = {
  opentopomap: JSON.stringify({
    version: 8,
    sources: {
      otm: {
        type: 'raster',
        tiles: [
          'https://a.tile.opentopomap.org/{z}/{x}/{y}.png',
          'https://b.tile.opentopomap.org/{z}/{x}/{y}.png',
          'https://c.tile.opentopomap.org/{z}/{x}/{y}.png',
        ],
        tileSize: 256,
        maxzoom: 17,
        attribution: '© OpenTopoMap (CC-BY-SA)',
      },
    },
    layers: [
      { id: 'otm-bg', type: 'background', paint: { 'background-color': '#F2EFE9' } },
      { id: 'otm-tiles', type: 'raster', source: 'otm' },
    ],
  }),

  'ign-plan': rasterStyleJson(
    'ign-plan',
    ignWmts('GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2', 'png'),
    18,
    '#F3F2EC',
    '© IGN-F / Géoplateforme',
  ),
  'ign-ortho': rasterStyleJson(
    'ign-ortho',
    ignWmts('ORTHOIMAGERY.ORTHOPHOTOS', 'jpeg'),
    19,
    '#2A2A2A',
    '© IGN-F / Géoplateforme',
  ),
};

export const MAP_STYLE_ORDER: MapStyleKey[] = [
  'outdoors',
  'ign-plan',
  'ign-ortho',
  'satellite-streets',
  'satellite',
  'streets',
  'opentopomap',
  'light',
  'dark',
];

export const MAP_STYLE_ATTRIBUTIONS: Partial<Record<MapStyleKey, string>> = {
  opentopomap: '© OpenTopoMap · OSM (CC-BY-SA)',
  'ign-plan': '© IGN-F / Géoplateforme',
  'ign-ortho': '© IGN-F / Géoplateforme',
};

const STORAGE_KEY = 'junto_map_style';
const DEFAULT_STYLE: MapStyleKey = 'outdoors';

interface MapStyleStore {
  style: MapStyleKey;
  loaded: boolean;
  load: () => Promise<void>;
  setStyle: (style: MapStyleKey) => void;
}

export const useMapStyleStore = create<MapStyleStore>((set) => ({
  style: DEFAULT_STYLE,
  loaded: false,
  load: async () => {
    try {
      const stored = await AsyncStorage.getItem(STORAGE_KEY);
      if (stored && (MAP_STYLE_ORDER as string[]).includes(stored)) {
        set({ style: stored as MapStyleKey, loaded: true });
      } else {
        set({ loaded: true });
      }
    } catch {
      set({ loaded: true });
    }
  },
  setStyle: (style) => {
    set({ style });
    AsyncStorage.setItem(STORAGE_KEY, style).catch(() => {});
  },
}));
