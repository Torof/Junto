import { useEffect, useMemo, useRef } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { BottomSheetModal, BottomSheetView } from '@gorhom/bottom-sheet';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useBottomTabBarHeight } from '@react-navigation/bottom-tabs';
import { useQuery } from '@tanstack/react-query';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { useTranslation } from 'react-i18next';
import { Calendar, BarChart2, MapPin, Car, Users, X, Clock, Lock, Route } from 'lucide-react-native';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { type NearbyActivity } from '@/services/activity-service';
import { transportService } from '@/services/transport-service';
import { getSportIcon } from '@/constants/sport-icons';
import { FavoriteButton } from './favorite-button';
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

// Interval → "3h" / "3h30" / "45min" (same parsing as the RA's duration).
function formatDuration(d: string | null): string | null {
  if (!d) return null;
  const match = d.match(/^(\d+):(\d+):/);
  if (!match) return d;
  const h = parseInt(match[1] ?? '0', 10);
  const m = parseInt(match[2] ?? '0', 10);
  if (h > 0 && m > 0) return `${h}h${m.toString().padStart(2, '0')}`;
  if (h > 0) return `${h}h`;
  return `${m}min`;
}

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
  const carRows = transportSummary.filter((r) => r.transport_type === 'car');
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
            <Pressable
              style={styles.closeBtn}
              onPress={() => modalRef.current?.dismiss()}
              hitSlop={8}
              accessibilityLabel={t('common.close', { defaultValue: 'Fermer' })}
            >
              <X size={22} color={colors.textPrimary} strokeWidth={2.4} />
            </Pressable>
            <FavoriteButton kind="activity" id={activity.id} size={21} style={styles.favBtn} />

            <View style={[styles.sportChip, { borderColor: accent, backgroundColor: accent + '18' }]}>
              <Text style={styles.sportEmoji}>{getSportIcon(activity.sport_key)}</Text>
              <Text style={[styles.sportChipText, { color: accent }]} numberOfLines={1}>
                {t(`sports.${activity.sport_key}`, { defaultValue: activity.sport_key })}
              </Text>
            </View>
            <View style={styles.kindRow}>
              {(activity.visibility === 'private_link' || activity.visibility === 'private_link_approval') && (
                <Lock size={12} color="#B45309" strokeWidth={2.6} />
              )}
              <Text style={[styles.kindLine, { color: accent }]} numberOfLines={1}>
                {t('map.peerOuting', { defaultValue: 'Sortie entre passionnés' })}
              </Text>
            </View>

            <Text style={styles.title} numberOfLines={2}>{activity.title}</Text>

            {/* One fact per line, icons in the universe color. */}
            <View style={styles.infoRow}>
              <Calendar size={15} color={accent} strokeWidth={2.2} />
              <Text style={styles.infoText}>
                {dayjs(activity.starts_at).locale(i18n.language).format('ddd D MMM [à] H[h]mm')}
              </Text>
            </View>

            {formatDuration(activity.duration) ? (
              <View style={styles.infoRow}>
                <Clock size={15} color={accent} strokeWidth={2.2} />
                <Text style={styles.infoText}>{formatDuration(activity.duration)}</Text>
              </View>
            ) : null}

            {(signal || activity.trace_geojson) ? (
              <View style={styles.infoRow}>
                <BarChart2 size={15} color={accent} strokeWidth={2.2} />
                {signal ? (
                  <Text style={styles.infoText} numberOfLines={1}>{signal}</Text>
                ) : (
                  <View style={{ flex: 1 }} />
                )}
                {activity.trace_geojson ? (
                  <View style={[styles.gpxPill, { borderColor: accent, backgroundColor: accent + '18' }]}>
                    <Route size={11} color={accent} strokeWidth={2.6} />
                    <Text style={[styles.gpxPillText, { color: accent }]}>GPX</Text>
                  </View>
                ) : null}
              </View>
            ) : null}

            <View style={styles.infoRow}>
              <Users size={15} color={accent} strokeWidth={2.2} />
              <Text style={[styles.infoText, isFull && { color: colors.error }]} numberOfLines={1}>
                {isOpenCount
                  ? `${activity.participant_count} ${t('map.participantsOpen', { defaultValue: 'participants · ouverte à tous' })}`
                  : isFull
                    ? t('map.full', { defaultValue: 'Complet' })
                    : t('map.spotsLeft', { defaultValue: '{{n}} places restantes', n: remaining, count: remaining })}
              </Text>
            </View>

            {activity.objective_name ? (
              <View style={styles.infoRow}>
                <MapPin size={15} color={accent} strokeWidth={2.2} />
                <Text style={styles.infoText} numberOfLines={1}>{activity.objective_name}</Text>
              </View>
            ) : null}

            {/* Carpool signal — "can I even get there" is decision info. */}
            {carSeats > 0 ? (
              <View style={styles.infoRow}>
                <Car size={15} color={accent} strokeWidth={2.2} />
                <Text style={styles.infoText} numberOfLines={1}>
                  {t('map.carpoolSeats', { defaultValue: '{{n}} places en covoit', n: carSeats, count: carSeats })}
                  {carCities.length > 0 ? ` · ${t('map.carpoolFrom', { defaultValue: 'dép.' })} ${carCities.slice(0, 2).join(', ')}${carCities.length > 2 ? '…' : ''}` : ''}
                </Text>
              </View>
            ) : null}

            <Pressable
              style={[styles.cta, { backgroundColor: accent, shadowColor: accent }]}
              onPress={() => onOpen(activity)}
              hitSlop={8}
            >
              <Text style={styles.ctaText}>{t('map.seeActivity', { defaultValue: 'Voir la sortie' })} →</Text>
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
  sportChip: {
    alignSelf: 'flex-start',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: radius.full,
    borderWidth: 1,
  },
  sportEmoji: { fontSize: 13 },
  sportChipText: { fontSize: 10, fontWeight: '800', letterSpacing: 0.6, textTransform: 'uppercase' },
  kindRow: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  kindLine: { fontSize: fontSizes.xs, fontWeight: '700' },
  closeBtn: { position: 'absolute', top: 2, right: spacing.lg, zIndex: 1, padding: 2 },
  favBtn: { position: 'absolute', top: 2, right: spacing.lg + 34, zIndex: 1, padding: 2 },
  title: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: '800', lineHeight: 26 },
  infoRow: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  infoText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600', flex: 1 },
  // "GPX" pill next to the difficulty — signals the outing carries a trace
  // (non-members can't open the map, so this is their only cue). Tinted with
  // the sport accent inline.
  gpxPill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 3,
    paddingHorizontal: 7,
    paddingVertical: 2,
    borderRadius: radius.full,
    borderWidth: 1,
  },
  gpxPillText: { fontSize: fontSizes.xs - 1, fontWeight: '800', letterSpacing: 0.4 },
  // Same visual language as the PP Aperçu "Voir tout →" links, one size up —
  // it's the teaser's primary action, not a section accessory.
  // Same grammar as the detail screen's join button — solid fill, lg
  // radius, soft tinted shadow — tinted per-activity with the sport
  // accent (bg + shadowColor applied inline).
  cta: {
    marginTop: spacing.sm,
    borderRadius: radius.lg,
    paddingVertical: spacing.md,
    alignItems: 'center',
    shadowOpacity: 0.35,
    shadowRadius: 12,
    shadowOffset: { width: 0, height: 6 },
    elevation: 5,
  },
  ctaText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '800' },
});
