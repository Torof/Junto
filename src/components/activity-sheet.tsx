import { useEffect, useMemo, useRef } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { BottomSheetModal, BottomSheetView } from '@gorhom/bottom-sheet';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useBottomTabBarHeight } from '@react-navigation/bottom-tabs';
import { useQuery } from '@tanstack/react-query';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { useTranslation } from 'react-i18next';
import { Calendar, BarChart2, MapPin, ChevronRight, Car } from 'lucide-react-native';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { type NearbyActivity } from '@/services/activity-service';
import { transportService } from '@/services/transport-service';
import { getSportIcon } from '@/constants/sport-icons';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { formatDifficultySignal } from '@/constants/sport-levels';
import { getRemainingPlaces } from '@/utils/activity-status';

// UA (peer outing) drawer — a pure TEASER (Scott, 2026-07-05): what catches the
// eye + what decides "do I want to know more", nothing else. Joining and the
// member surfaces (chat / covoiturage / matos) live on the full page behind the
// single CTA — opening the page to join is what makes people discover those
// tabs. No map inside (the pin is literally visible above the drawer); the one
// org signal shown pre-join is the carpool summary (get_transport_summary is
// deliberately readable by non-participants, audit 00196) because "can I even
// get there" IS decision info. Content is short, so one content-hugging height
// (enableDynamicSizing) instead of the PP/RA two-stage collapse; same modal
// shell (present/dismiss, lip border, sheet shadow, above the tab bar).

interface Props {
  // The selected activity, or null. Always mounted; present()/dismiss() follow.
  activity: NearbyActivity | null;
  onClose: () => void;
  // CTA → the full activity page.
  onOpen: (activity: NearbyActivity) => void;
}

export function ActivitySheet({ activity, onClose, onOpen }: Props) {
  const { t, i18n } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const modalRef = useRef<BottomSheetModal>(null);
  const insets = useSafeAreaInsets();
  const tabBarHeight = useBottomTabBarHeight();

  useEffect(() => {
    if (activity) modalRef.current?.present();
    else modalRef.current?.dismiss();
  }, [activity]);

  const accent = activity ? sportCategoryColor(activity.sport_category, colors.cta) : colors.cta;

  const signal = activity
    ? formatDifficultySignal(activity.sport_key, activity.level, activity.distance_km, activity.elevation_gain_m, activity.level_max)
    : null;
  const remaining = activity ? getRemainingPlaces(activity.max_participants, activity.participant_count) : 0;
  const isOpenCount = activity?.max_participants === null;
  const isFull = !isOpenCount && remaining <= 0;

  // Carpool summary — car/carpool rows only: seats offered + departure cities.
  const { data: transportSummary = [] } = useQuery({
    queryKey: ['transport-summary', activity?.id],
    queryFn: () => transportService.getSummary(activity!.id),
    enabled: !!activity,
  });
  const carRows = transportSummary.filter((r) => r.transport_type === 'car' || r.transport_type === 'carpool');
  const carSeats = carRows.reduce((sum, r) => sum + (r.total_seats ?? 0), 0);
  const carCities = [...new Set(carRows.flatMap((r) => r.cities ?? []))];

  return (
    <BottomSheetModal
      ref={modalRef}
      topInset={insets.top}
      bottomInset={tabBarHeight}
      enablePanDownToClose
      enableDynamicSizing
      onDismiss={onClose}
      backgroundStyle={styles.bg}
      handleComponent={() => (
        <View style={styles.handle}>
          <View style={styles.grabber} />
        </View>
      )}
    >
      <BottomSheetView style={styles.content}>
        {activity ? (
          <>
            <View style={styles.chipRow}>
              <View style={[styles.sportChip, { borderColor: accent, backgroundColor: accent + '18' }]}>
                <Text style={styles.sportEmoji}>{getSportIcon(activity.sport_key)}</Text>
                <Text style={[styles.sportChipText, { color: accent }]} numberOfLines={1}>
                  {t(`sports.${activity.sport_key}`, { defaultValue: activity.sport_key })}
                </Text>
              </View>
              <View style={styles.whenRow}>
                <Calendar size={14} color={colors.textPrimary} strokeWidth={2.2} />
                <Text style={styles.whenText}>
                  {dayjs(activity.starts_at).locale(i18n.language).format('ddd D MMM [·] H[h]mm')}
                </Text>
              </View>
            </View>

            <Text style={styles.title} numberOfLines={2}>{activity.title}</Text>

            {/* Decision line: difficulty signal · places */}
            <View style={styles.signalRow}>
              {signal ? (
                <View style={styles.signalItem}>
                  <BarChart2 size={13} color={colors.textSecondary} strokeWidth={2.2} />
                  <Text style={styles.signalText} numberOfLines={1}>{signal}</Text>
                </View>
              ) : null}
              <View style={[styles.placesChip, isFull && styles.placesChipFull]}>
                <Text style={[styles.placesChipText, isFull && styles.placesChipTextFull]}>
                  {isOpenCount
                    ? `${activity.participant_count} · ${t('create.openActivityValue', { defaultValue: 'ouvert' })}`
                    : `${activity.participant_count}/${activity.max_participants} ${t('activity.places', { defaultValue: 'places' })}`}
                </Text>
              </View>
            </View>

            {activity.objective_name ? (
              <View style={styles.placeRow}>
                <MapPin size={14} color={accent} strokeWidth={2.2} />
                <Text style={styles.placeText} numberOfLines={1}>{activity.objective_name}</Text>
              </View>
            ) : null}

            {/* Carpool signal — "can I even get there" is decision info. */}
            {carSeats > 0 ? (
              <View style={styles.placeRow}>
                <Car size={14} color={colors.textSecondary} strokeWidth={2.2} />
                <Text style={styles.carpoolText} numberOfLines={1}>
                  {t('map.carpoolSeats', { defaultValue: '{{n}} places en covoit', n: carSeats, count: carSeats })}
                  {carCities.length > 0 ? ` · ${t('map.carpoolFrom', { defaultValue: 'dép.' })} ${carCities.slice(0, 2).join(', ')}${carCities.length > 2 ? '…' : ''}` : ''}
                </Text>
              </View>
            ) : null}

            <Pressable style={styles.cta} onPress={() => onOpen(activity)}>
              <Text style={styles.ctaText}>{t('map.seeActivity', { defaultValue: 'Voir la sortie' })}</Text>
              <ChevronRight size={17} color={colors.background} strokeWidth={2.6} />
            </Pressable>
          </>
        ) : null}
      </BottomSheetView>
    </BottomSheetModal>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  bg: {
    backgroundColor: colors.surfaceAlt,
    borderTopLeftRadius: radius.xl,
    borderTopRightRadius: radius.xl,
    ...shadows.sheet,
  },
  handle: {
    alignItems: 'center',
    paddingTop: 10,
    paddingBottom: 6,
    backgroundColor: colors.surfaceAlt,
    borderTopLeftRadius: radius.xl,
    borderTopRightRadius: radius.xl,
    borderTopWidth: 1,
    borderLeftWidth: 1,
    borderRightWidth: 1,
    borderColor: colors.borderMuted,
  },
  grabber: { height: 4, width: 40, borderRadius: 2, backgroundColor: colors.textMuted },
  content: {
    paddingHorizontal: spacing.lg,
    paddingBottom: spacing.lg,
    gap: spacing.sm,
  },
  chipRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: spacing.sm },
  sportChip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: radius.full,
    borderWidth: 1,
    flexShrink: 1,
    minWidth: 0,
  },
  sportEmoji: { fontSize: 13 },
  sportChipText: { fontSize: 10, fontWeight: '800', letterSpacing: 0.6, textTransform: 'uppercase' },
  whenRow: { flexDirection: 'row', alignItems: 'center', gap: 5 },
  whenText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700' },
  title: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: '800', lineHeight: 26 },
  signalRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, flexWrap: 'wrap' },
  signalItem: { flexDirection: 'row', alignItems: 'center', gap: 4, flexShrink: 1, minWidth: 0 },
  signalText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600' },
  placesChip: { backgroundColor: colors.success + '33', paddingHorizontal: 8, paddingVertical: 2, borderRadius: radius.full },
  placesChipFull: { backgroundColor: colors.error + '33' },
  placesChipText: { color: colors.success, fontSize: fontSizes.xs, fontWeight: '800', letterSpacing: 0.4 },
  placesChipTextFull: { color: colors.error },
  placeRow: { flexDirection: 'row', alignItems: 'center', gap: 5 },
  placeText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600', flex: 1 },
  carpoolText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600', flex: 1 },
  cta: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 4,
    backgroundColor: colors.cta,
    borderRadius: radius.md,
    paddingVertical: spacing.sm + 2,
    marginTop: spacing.xs,
  },
  ctaText: { color: colors.background, fontSize: fontSizes.md, fontWeight: '800' },
});
