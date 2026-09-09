import { useMemo } from 'react';
import { View, Text, Pressable, StyleSheet, ActivityIndicator } from 'react-native';
import { Image } from 'expo-image';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { useTranslation } from 'react-i18next';
import { Calendar, MapPin, Users, ArrowRight } from 'lucide-react-native';
import { useQuery } from '@tanstack/react-query';
import { fontSizes, spacing, shadows } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { activityService } from '@/services/activity-service';
import { formatDifficultySignal } from '@/constants/sport-levels';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { getSportIcon } from '@/constants/sport-icons';

const MAPBOX_TOKEN = process.env.EXPO_PUBLIC_MAPBOX_ACCESS_TOKEN;

interface SharedActivityCardProps {
  activityId: string;
  onPress: (activityId: string) => void;
  /** Shown while the activity loads and if the fetch fails (from the message content). */
  fallbackTitle?: string | null;
}

// Full-width "shared outing" card rendered inside a channel/DM thread.
// Mirrors the activity list card language (sport pill + level, date · place ·
// seats) with a Mapbox static hero of the objective/meeting location — so a
// shared outing reads as an outing, not a cramped text bubble.
export function SharedActivityCard({ activityId, onPress, fallbackTitle }: SharedActivityCardProps) {
  const { t, i18n } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const { data: activity, isLoading } = useQuery({
    queryKey: ['shared-activity', activityId],
    queryFn: () => activityService.getById(activityId),
    staleTime: 60_000,
  });

  if (isLoading && !activity) {
    return (
      <Pressable style={styles.card} onPress={() => onPress(activityId)}>
        <View style={styles.loadingBox}>
          <ActivityIndicator color={colors.textSecondary} />
          {!!fallbackTitle && (
            <Text style={styles.loadingTitle} numberOfLines={2}>{fallbackTitle}</Text>
          )}
        </View>
      </Pressable>
    );
  }

  // Unavailable (deleted / private / not accessible) — keep it tappable so the
  // detail screen owns its own "unavailable" state.
  if (!activity) {
    return (
      <Pressable style={styles.card} onPress={() => onPress(activityId)}>
        <View style={styles.body}>
          <Text style={styles.title} numberOfLines={2}>
            {fallbackTitle ?? t('messagerie.previewActivity')}
          </Text>
          <View style={styles.ctaRow}>
            <Text style={styles.ctaText}>{t('messagerie.viewActivity')}</Text>
            <ArrowRight size={15} color={colors.cta} strokeWidth={2.6} />
          </View>
        </View>
      </Pressable>
    );
  }

  const sportAccent = sportCategoryColor(activity.sport_category, colors.cta);
  const signal = formatDifficultySignal(
    activity.sport_key,
    activity.level,
    activity.distance_km,
    activity.elevation_gain_m,
    activity.level_max,
  );
  const datePart = dayjs(activity.starts_at).locale(i18n.language).format('ddd D MMM · H[h]mm');
  const place = activity.objective_name ?? activity.meeting_name ?? null;

  // Prefer the objective (summit/spot); fall back to the meeting point, then
  // the anchored coord the map row exposes.
  const heroLng = activity.objective_lng ?? activity.meeting_lng ?? activity.lng;
  const heroLat = activity.objective_lat ?? activity.meeting_lat ?? activity.lat;
  const mapUrl =
    MAPBOX_TOKEN && heroLng != null && heroLat != null
      ? `https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/static/${heroLng},${heroLat},11.5,0/640x264@2x?access_token=${MAPBOX_TOKEN}`
      : null;

  return (
    <Pressable style={styles.card} onPress={() => onPress(activity.id)}>
      <View style={styles.hero}>
        {mapUrl ? (
          <Image source={{ uri: mapUrl }} style={StyleSheet.absoluteFill} contentFit="cover" transition={150} />
        ) : (
          <View style={[StyleSheet.absoluteFill, styles.heroFallback, { backgroundColor: sportAccent + '22' }]} />
        )}
        <View style={styles.heroPin}>
          <Text style={styles.heroPinIcon}>{getSportIcon(activity.sport_key)}</Text>
        </View>
        <View style={styles.heroPills}>
          <View style={[styles.pill, { backgroundColor: sportAccent }]}>
            <Text style={styles.pillSportText} numberOfLines={1}>
              {t(`sports.${activity.sport_key}`, activity.sport_key)}
            </Text>
          </View>
          {!!signal && (
            <View style={[styles.pill, styles.pillLevel]}>
              <Text style={[styles.pillLevelText, { color: sportAccent }]} numberOfLines={1}>{signal}</Text>
            </View>
          )}
        </View>
      </View>

      <View style={styles.body}>
        <Text style={styles.title} numberOfLines={2}>{activity.title}</Text>
        <View style={styles.metaRow}>
          <View style={styles.metaItem}>
            <Calendar size={12} color={colors.textSecondary} strokeWidth={2.4} />
            <Text style={styles.metaText} numberOfLines={1}>{datePart}</Text>
          </View>
          {!!place && (
            <View style={[styles.metaItem, { flexShrink: 1 }]}>
              <MapPin size={12} color={colors.textSecondary} strokeWidth={2.4} />
              <Text style={styles.metaText} numberOfLines={1}>{place}</Text>
            </View>
          )}
          <View style={styles.metaItem}>
            <Users size={12} color={colors.textSecondary} strokeWidth={2.4} />
            <Text style={styles.metaText} numberOfLines={1}>
              {activity.participant_count}
              {activity.max_participants !== null ? `/${activity.max_participants}` : ''}
            </Text>
          </View>
        </View>
        <View style={styles.ctaRow}>
          <Text style={styles.ctaText}>{t('messagerie.viewActivity')}</Text>
          <ArrowRight size={15} color={colors.cta} strokeWidth={2.6} />
        </View>
      </View>
    </Pressable>
  );
}

const createStyles = (colors: AppColors) =>
  StyleSheet.create({
    card: {
      borderRadius: 16,
      overflow: 'hidden',
      borderWidth: 1,
      borderColor: colors.border,
      backgroundColor: colors.background,
      ...shadows.card,
    },
    loadingBox: {
      minHeight: 88,
      alignItems: 'center',
      justifyContent: 'center',
      gap: spacing.sm,
      padding: spacing.md,
    },
    loadingTitle: {
      fontSize: fontSizes.sm,
      fontWeight: '700',
      color: colors.textSecondary,
      textAlign: 'center',
    },
    hero: {
      height: 128,
      justifyContent: 'center',
      alignItems: 'center',
    },
    heroFallback: {
      justifyContent: 'center',
      alignItems: 'center',
    },
    heroPin: {
      width: 40,
      height: 40,
      borderRadius: 20,
      backgroundColor: '#FFFFFF',
      alignItems: 'center',
      justifyContent: 'center',
      ...shadows.raised,
    },
    heroPinIcon: {
      fontSize: 20,
    },
    heroPills: {
      position: 'absolute',
      top: spacing.sm,
      left: spacing.sm,
      right: spacing.sm,
      flexDirection: 'row',
      flexWrap: 'wrap',
      gap: 6,
    },
    pill: {
      paddingVertical: 5,
      paddingHorizontal: 10,
      borderRadius: 999,
    },
    pillSportText: {
      fontSize: fontSizes.xs,
      fontWeight: '800',
      color: '#FFFFFF',
    },
    pillLevel: {
      backgroundColor: 'rgba(255,255,255,0.94)',
    },
    pillLevelText: {
      fontSize: fontSizes.xs,
      fontWeight: '800',
    },
    body: {
      paddingHorizontal: spacing.md,
      paddingTop: spacing.sm + 2,
      paddingBottom: spacing.sm + 2,
      gap: 7,
    },
    title: {
      fontSize: fontSizes.md,
      fontWeight: '800',
      color: colors.textPrimary,
      lineHeight: 21,
    },
    metaRow: {
      flexDirection: 'row',
      flexWrap: 'wrap',
      alignItems: 'center',
      gap: 4,
    },
    metaItem: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 4,
      marginRight: spacing.sm,
    },
    metaText: {
      fontSize: fontSizes.sm,
      fontWeight: '700',
      color: colors.textSecondary,
    },
    ctaRow: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      marginTop: 3,
      paddingTop: spacing.sm,
      borderTopWidth: 1,
      borderTopColor: colors.borderMuted,
    },
    ctaText: {
      fontSize: fontSizes.sm,
      fontWeight: '800',
      color: colors.cta,
    },
  });
