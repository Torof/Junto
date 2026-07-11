import { useState, useCallback, useEffect, useRef, useMemo } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { JuntoMapView, type MapBounds } from '@/components/map-view';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { useNearbyActivities, type MapBounds as QueryBounds } from '@/hooks/use-nearby-activities';

export default function VisitorMapScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const { center } = useInitialLocation();

  const [searchBounds, setSearchBounds] = useState<QueryBounds | null>(null);
  const lastSearchCenter = useRef<{ lng: number; lat: number } | null>(null);
  const currentBounds = useRef<MapBounds | null>(null);
  const initialSearchDone = useRef(false);
  const searchDebounce = useRef<ReturnType<typeof setTimeout> | null>(null);

  const { data: activities } = useNearbyActivities(searchBounds);

  const doSearch = useCallback((bounds: MapBounds) => {
    lastSearchCenter.current = { lng: bounds.centerLng, lat: bounds.centerLat };
    const lngSpan = bounds.neLng - bounds.swLng;
    const latSpan = bounds.neLat - bounds.swLat;
    setSearchBounds({
      swLng: bounds.swLng - lngSpan * 0.5,
      swLat: bounds.swLat - latSpan * 0.5,
      neLng: bounds.neLng + lngSpan * 0.5,
      neLat: bounds.neLat + latSpan * 0.5,
    });
  }, []);

  const scheduleSearch = useCallback((bounds: MapBounds) => {
    if (searchDebounce.current) clearTimeout(searchDebounce.current);
    searchDebounce.current = setTimeout(() => {
      doSearch(bounds);
      searchDebounce.current = null;
    }, 500);
  }, [doSearch]);

  useEffect(() => {
    return () => {
      if (searchDebounce.current) clearTimeout(searchDebounce.current);
    };
  }, []);

  const handleBoundsChange = useCallback((bounds: MapBounds) => {
    currentBounds.current = bounds;

    if (!initialSearchDone.current) {
      initialSearchDone.current = true;
      doSearch(bounds);
      return;
    }

    if (searchBounds && !(bounds.swLng >= searchBounds.swLng && bounds.swLat >= searchBounds.swLat && bounds.neLng <= searchBounds.neLng && bounds.neLat <= searchBounds.neLat)) {
      if (searchDebounce.current) {
        clearTimeout(searchDebounce.current);
        searchDebounce.current = null;
      }
      doSearch(bounds);
      return;
    }

    if (lastSearchCenter.current) {
      const viewportWidth = Math.abs(bounds.neLng - bounds.swLng);
      const dlat = bounds.centerLat - lastSearchCenter.current.lat;
      const dlng = bounds.centerLng - lastSearchCenter.current.lng;
      if (Math.sqrt(dlat * dlat + dlng * dlng) > viewportWidth * 0.3) {
        scheduleSearch(bounds);
      }
    }
  }, [searchBounds, doSearch, scheduleSearch]);

  return (
    <View style={styles.container}>
      <SafeAreaView edges={['top']} style={styles.statusBar} />

      <View style={styles.banner}>
        <Text style={styles.bannerText}>{t('visitor.explore')}</Text>
        <Pressable style={styles.signInButton} onPress={() => router.push('/(visitor)/login')}>
          <Text style={styles.signInText}>{t('auth.signIn')}</Text>
        </Pressable>
      </View>

      {/* Pre-login teaser map: pins only — no popup, no drawer, no tap
          target (Scott 2026-07-11). The pins show there's activity nearby;
          discovering details is what signing in is for. */}
      <JuntoMapView
        center={center}
        activities={activities ?? []}
        onBoundsChange={handleBoundsChange}
      />
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  statusBar: {
    backgroundColor: colors.background,
  },
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
