import { create } from 'zustand';
import AsyncStorage from '@react-native-async-storage/async-storage';

export type MapStyleKey =
  | 'outdoors'
  | 'streets'
  | 'satellite-streets'
  | 'opentopomap'
  | 'ign-plan';

export const MAP_STYLE_URLS: Partial<Record<MapStyleKey, string>> = {
  outdoors: 'mapbox://styles/mapbox/outdoors-v12',
  streets: 'mapbox://styles/mapbox/streets-v12',
  'satellite-streets': 'mapbox://styles/mapbox/satellite-streets-v12',
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
};

export const MAP_STYLE_ORDER: MapStyleKey[] = [
  'outdoors',       // Outdoor
  'ign-plan',       // Carte IGN
  'satellite-streets', // Satellite
  'streets',        // Maps
  'opentopomap',    // OSM
];

export const MAP_STYLE_ATTRIBUTIONS: Partial<Record<MapStyleKey, string>> = {
  opentopomap: '© OpenTopoMap · OSM (CC-BY-SA)',
  'ign-plan': '© IGN-F / Géoplateforme',
};

const STORAGE_KEY = 'junto_map_style';
const SECONDARY_STORAGE_KEY = 'junto_map_style_secondary';
const DEFAULT_STYLE: MapStyleKey = 'outdoors';

// Which map a style applies to: the main map (carte tab, visitor map) or every
// secondary map (trace library and drawing, an outing's or a pro's full map,
// pickers, previews) — two independent, remembered choices (Scott 2026-10-30).
export type MapStyleScope = 'main' | 'secondary';

interface MapStyleStore {
  style: MapStyleKey;
  secondaryStyle: MapStyleKey;
  loaded: boolean;
  load: () => Promise<void>;
  setStyle: (style: MapStyleKey) => void;
  setSecondaryStyle: (style: MapStyleKey) => void;
}

export const useMapStyleStore = create<MapStyleStore>((set) => ({
  style: DEFAULT_STYLE,
  secondaryStyle: DEFAULT_STYLE,
  loaded: false,
  load: async () => {
    const valid = (v: string | null): v is MapStyleKey => !!v && (MAP_STYLE_ORDER as string[]).includes(v);
    try {
      const [stored, storedSecondary] = await Promise.all([
        AsyncStorage.getItem(STORAGE_KEY),
        AsyncStorage.getItem(SECONDARY_STORAGE_KEY),
      ]);
      set({
        ...(valid(stored) ? { style: stored } : {}),
        ...(valid(storedSecondary) ? { secondaryStyle: storedSecondary } : {}),
        loaded: true,
      });
    } catch {
      set({ loaded: true });
    }
  },
  setStyle: (style) => {
    set({ style });
    AsyncStorage.setItem(STORAGE_KEY, style).catch(() => {});
  },
  setSecondaryStyle: (secondaryStyle) => {
    set({ secondaryStyle });
    AsyncStorage.setItem(SECONDARY_STORAGE_KEY, secondaryStyle).catch(() => {});
  },
}));
