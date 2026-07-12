import { useState, useCallback, useEffect, useRef, useMemo } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import * as Updates from 'expo-updates';
import { JuntoMapView, type MapBounds } from '@/components/map-view';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { useNearbyActivities, type MapBounds as QueryBounds } from '@/hooks/use-nearby-activities';

export default function VisitorMapScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const { center } = useInitialLocation();

  // TEMP build/OTA marker so Scott can confirm which version his phone is
  // actually running (remove once the map bug is settled, 2026-07-12).
  const buildTag = (() => {
    const ch = Updates.channel ?? 'dev';
    if (Updates.isEmbeddedLaunch) return `${ch} · build (pas d'OTA)`;
    const at = Updates.createdAt;
    const hhmm = at ? `${String(at.getHours()).padStart(2, '0')}:${String(at.getMinutes()).padStart(2, '0')}` : '?';
    return `${ch} · OTA ${hhmm}`;
  })();

  const [searchBounds, setSearchBounds] = useState<QueryBounds | null>(null);
  const lastSearchCenter = useRef<{ lng: number; lat: number } | null>(null);
  const currentBounds = useRef<MapBounds | null>(null);
  const initialSearchDone = useRef(false);
  const searchDebounce = useRef<ReturnType<typeof setTimeout> | null>(null);

  const { data: activities } = useNearbyActivities(searchBounds);

  // Pre-login teaser map: fetch a GENEROUS area (2x the viewport each side
  // = 5x span) so panning around stays inside the fetched buffer and never
  // triggers a refetch. Each refetch rebuilds the Supercluster and churns
  // cluster ids → markers remount → pins "blink off/on" (Scott 2026-07-12).
  // Only a large move past the buffer refetches, debounced.
  const doSearch = useCallback((bounds: MapBounds) => {
    lastSearchCenter.current = { lng: bounds.centerLng, lat: bounds.centerLat };
    const lngSpan = bounds.neLng - bounds.swLng;
    const latSpan = bounds.neLat - bounds.swLat;
    setSearchBounds({
      swLng: bounds.swLng - lngSpan * 2,
      swLat: bounds.swLat - latSpan * 2,
      neLng: bounds.neLng + lngSpan * 2,
      neLat: bounds.neLat + latSpan * 2,
    });
  }, []);

  const scheduleSearch = useCallback((bounds: MapBounds) => {
    if (searchDebounce.current) clearTimeout(searchDebounce.current);
    searchDebounce.current = setTimeout(() => {
      doSearch(bounds);
      searchDebounce.current = null;
    }, 700);
  }, [doSearch]);

  useEffect(() => {
    return () => {
      if (searchDebounce.current) clearTimeout(searchDebounce.current);
    };
  }, []);

  // Kick off the first fetch immediately from the known center instead of
  // waiting for the map's first camera event (startup bumps + GPS resolve
  // could push pins to ~10s — Scott 2026-07-12). Generous ~35km box covers
  // the teaser viewport; the camera-driven search takes over for real pans.
  useEffect(() => {
    if (initialSearchDone.current) return;
    initialSearchDone.current = true;
    const half = 0.35;
    doSearch({
      swLng: center[0] - half, swLat: center[1] - half,
      neLng: center[0] + half, neLat: center[1] + half,
      centerLng: center[0], centerLat: center[1],
    });
  }, [center, doSearch]);

  const handleBoundsChange = useCallback((bounds: MapBounds) => {
    currentBounds.current = bounds;

    if (!initialSearchDone.current) {
      initialSearchDone.current = true;
      doSearch(bounds);
      return;
    }

    // Only refetch when the viewport has left the generous fetched buffer,
    // and even then debounced — no immediate refetch, no per-pan churn.
    if (searchBounds && !(bounds.swLng >= searchBounds.swLng && bounds.swLat >= searchBounds.swLat && bounds.neLng <= searchBounds.neLng && bounds.neLat <= searchBounds.neLat)) {
      scheduleSearch(bounds);
    }
  }, [searchBounds, doSearch, scheduleSearch]);

  return (
    <View style={styles.container}>
      {/* Map as the base layer, filling the whole screen (same structure as
          the authenticated carte). The banner is a separate absolute
          overlay — NOT a flex sibling that steals height and shifts the
          map's viewport, which clipped pins near the bottom (Scott's
          "line eating the pins", 2026-07-12).
          Pre-login teaser: pins only — no popup, no drawer, no tap. */}
      <View style={styles.content}>
        <JuntoMapView
          center={center}
          activities={activities ?? []}
          onBoundsChange={handleBoundsChange}
        />
      </View>

      <View style={styles.buildTag} pointerEvents="none">
        <Text style={styles.buildTagText}>{buildTag}</Text>
      </View>

      <View style={styles.banner}>
        <Text style={styles.bannerText}>{t('visitor.explore')}</Text>
        <Pressable style={styles.signInButton} onPress={() => router.push('/(visitor)/login')}>
          <Text style={styles.signInText}>{t('auth.signIn')}</Text>
        </Pressable>
      </View>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  // Same as the authenticated carte: the map's wrapper is a plain flex:1
  // child (NOT absoluteFill — that broke MarkerView rendering). Sole
  // flex-flow child, so it fills the screen; banner overlays absolutely.
  content: {
    flex: 1,
  },
  buildTag: {
    position: 'absolute',
    bottom: 8,
    alignSelf: 'center',
    backgroundColor: 'rgba(0,0,0,0.55)',
    borderRadius: 8,
    paddingHorizontal: 10,
    paddingVertical: 3,
    zIndex: 20,
  },
  buildTagText: { color: '#FFFFFF', fontSize: 11, fontWeight: '600' },
  banner: {
    position: 'absolute',
    top: 95,
    left: spacing.md,
    right: spacing.md,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: colors.background + 'F0',
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    zIndex: 10,
  },
  bannerText: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    flex: 1,
    marginRight: spacing.md,
  },
  signInButton: {
    backgroundColor: colors.cta,
    borderRadius: radius.full,
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.sm,
  },
  signInText: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: 'bold',
  },
});
