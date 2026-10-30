import { useMemo } from 'react';
import { View, Pressable, StyleSheet } from 'react-native';
import { AppText } from '@/components/app-text';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { X } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { JuntoMapView } from '@/components/map-view';
import { MapStyleButton } from '@/components/map-style-button';
import { LogoSpinner } from '@/components/logo-spinner';
import { discoveryService } from '@/services/discovery-service';

// Reads a dispo's availability zone (base + radius) onto a Mapbox map. My own
// zone is passed directly (lng/lat/radius params); a match's zone is fetched
// via get_dispo_zone (server-gated to people who already match me).
export default function DiscoveryZoneScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const params = useLocalSearchParams<{
    lng?: string; lat?: string; radius?: string; label?: string; userId?: string; name?: string;
  }>();

  const direct = params.lng != null && params.lat != null;
  const { data: zone, isLoading } = useQuery({
    queryKey: ['dispo-zone', params.userId],
    queryFn: () => discoveryService.getDispoZone(params.userId as string),
    enabled: !direct && !!params.userId,
  });

  const coords = direct
    ? { lng: Number(params.lng), lat: Number(params.lat), radius: params.radius ? Number(params.radius) : null }
    : zone
      ? { lng: zone.base_lng, lat: zone.base_lat, radius: zone.radius_km }
      : null;

  const title = params.label ?? params.name ?? t('discovery.zoneTitle', { defaultValue: 'Zone de dispo' });

  return (
    <View style={[styles.container, { paddingTop: insets.top }]}>
      <View style={styles.header}>
        <Pressable onPress={() => router.back()} hitSlop={8}><X size={24} color={colors.textPrimary} strokeWidth={2.2} /></Pressable>
        <AppText style={styles.headerTitle} numberOfLines={1}>{title}</AppText>
        <View style={{ width: 24 }} />
      </View>

      {isLoading ? (
        <View style={styles.center}><LogoSpinner size={40} /></View>
      ) : !coords ? (
        <View style={styles.center}>
          <AppText style={styles.unavailable}>{t('discovery.zoneUnavailable', { defaultValue: 'Zone indisponible.' })}</AppText>
        </View>
      ) : (
        <View style={styles.mapWrap}>
          <JuntoMapView
            center={[coords.lng, coords.lat]}
            zoom={10}
            radiusKm={coords.radius}
            radiusCenter={[coords.lng, coords.lat]}
            tapMarker={[coords.lng, coords.lat]}
            tapMarkerContent={<View style={styles.pin} />}
            rotateEnabled={false}
            pitchEnabled={false}
          />
          <MapStyleButton scope="secondary" style={styles.mapStyleButton} />
          <View style={[styles.caption, { bottom: insets.bottom + spacing.md }]} pointerEvents="none">
            <AppText style={styles.captionText}>
              {coords.radius
                ? t('discovery.zoneRadius', { defaultValue: 'Dispo dans un rayon de {{km}} km', km: coords.radius })
                : t('discovery.zoneAny', { defaultValue: 'Dispo peu importe la distance' })}
            </AppText>
          </View>
        </View>
      )}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: spacing.md, paddingVertical: spacing.md, gap: spacing.md },
  headerTitle: { flex: 1, textAlign: 'center', color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800' },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: spacing.xl },
  unavailable: { color: colors.textSecondary, fontSize: fontSizes.md, textAlign: 'center' },
  mapWrap: { flex: 1 },
  mapStyleButton: { position: 'absolute', top: spacing.md, right: spacing.md },
  pin: { width: 18, height: 18, borderRadius: 9, backgroundColor: colors.cta, borderWidth: 3, borderColor: '#FFFFFF' },
  caption: { position: 'absolute', left: spacing.md, right: spacing.md, alignItems: 'center' },
  captionText: {
    backgroundColor: colors.surface,
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '700',
    borderRadius: 999,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    overflow: 'hidden',
  },
});
