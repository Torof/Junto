import { useMemo } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { useTranslation } from 'react-i18next';
import { Calendar, BarChart2, ChevronRight } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { type NearbyActivity } from '@/services/activity-service';
import { formatDifficultySignal } from '@/constants/sport-levels';
import { getRemainingPlaces } from '@/utils/activity-status';
import { sportCategoryColor } from '@/utils/sport-category-color';

interface ActivityPopupProps {
  activity: NearbyActivity;
  onPress: () => void;
}

export function ActivityPopup({ activity, onPress }: ActivityPopupProps) {
  const { t, i18n } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const remaining = getRemainingPlaces(activity.max_participants, activity.participant_count);
  const isFull = remaining <= 0;
  const isOpen = activity.max_participants === null;
  const sportAccent = sportCategoryColor(activity.sport_category, colors.cta);

  return (
    <Pressable style={styles.card} onPress={onPress}>
      {/* Title */}
      <Text style={styles.title} numberOfLines={2}>
        {activity.title}
      </Text>

      {/* Sport + places chips on same row */}
      <View style={styles.chipsRow}>
        <View style={[styles.sportChip, { backgroundColor: sportAccent + '40', borderColor: sportAccent }]}>
          <Text style={[styles.sportChipText, { color: sportAccent }]}>
            {t(`sports.${activity.sport_key}`, activity.sport_key)}
          </Text>
        </View>
        <View style={[styles.placesChip, isFull && styles.placesChipFull]}>
          <Text style={[styles.placesChipText, isFull && styles.placesChipTextFull]}>
            {isOpen ? `${activity.participant_count} · ${t('create.openActivityValue')}` : `${activity.participant_count}/${activity.max_participants}`}
          </Text>
        </View>
      </View>

      {activity.objective_name && (
        <Text style={styles.objectiveName} numberOfLines={1}>📍 {activity.objective_name}</Text>
      )}

      {/* Date */}
      <View style={styles.row}>
        <Calendar size={12} color={colors.textPrimary} strokeWidth={2} />
        <Text style={styles.value}>
          {dayjs(activity.starts_at).locale(i18n.language).format('ddd D MMM · H[h]mm')}
        </Text>
      </View>

      {/* Difficulty signal — sport-adaptive */}
      {(() => {
        const signal = formatDifficultySignal(activity.sport_key, activity.level, activity.distance_km, activity.elevation_gain_m, activity.level_max);
        if (!signal) return null;
        return (
          <>
            <View style={styles.divider} />
            <View style={styles.row}>
              <BarChart2 size={12} color={colors.textPrimary} strokeWidth={2} />
              <Text style={styles.value}>{signal}</Text>
            </View>
          </>
        );
      })()}

      {/* Affordance — testers tapped pins but not the open popup; this
          makes "tap to open the full activity" explicit. */}
      <View style={styles.seeMore}>
        <Text style={styles.seeMoreText}>{t('map.seeMore')}</Text>
        <ChevronRight size={12} color={colors.cta} strokeWidth={2.5} />
      </View>
    </Pressable>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  card: {
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.md,
    elevation: 10,
    shadowColor: '#0A0F1A',
    shadowOffset: { width: 0, height: 6 },
    shadowOpacity: 0.25,
    shadowRadius: 14,
    borderWidth: 1.5,
    borderColor: colors.borderStrong,
    minWidth: 170,
    gap: spacing.xs,
  },
  chipsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    marginBottom: 2,
  },
  sportChip: {
    backgroundColor: colors.cta + '1F',
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 999,
    borderWidth: 1,
  },
  sportChipText: {
    color: colors.cta,
    fontSize: 10,
    fontWeight: '800',
    letterSpacing: 0.6,
    textTransform: 'uppercase',
  },
  placesChip: {
    backgroundColor: colors.success + '33',
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 999,
  },
  placesChipFull: {
    backgroundColor: colors.error + '33',
  },
  placesChipText: {
    color: colors.success,
    fontSize: 9,
    fontWeight: '700',
    letterSpacing: 0.6,
  },
  placesChipTextFull: {
    color: colors.error,
  },
  title: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    fontWeight: 'bold',
    marginBottom: 2,
  },
  objectiveName: {
    color: colors.textPrimary,
    fontSize: fontSizes.xs,
    fontWeight: '600',
    marginBottom: 2,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
  },
  label: {
    fontSize: 10,
  },
  value: {
    color: colors.textPrimary,
    fontSize: fontSizes.xs,
    fontWeight: '600',
  },
  divider: {
    height: 1,
    backgroundColor: colors.textSecondary,
    opacity: 0.35,
    marginVertical: 2,
  },
  seeMore: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'flex-end',
    gap: 2,
    marginTop: 2,
  },
  seeMoreText: {
    color: colors.cta,
    fontSize: fontSizes.xs,
    fontWeight: '700',
  },
  spacer: {
    width: spacing.sm,
  },
  spotDot: {
    width: 6,
    height: 6,
    borderRadius: 3,
  },
  spotText: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: 'bold',
  },
});
