import { useMemo } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { useTranslation } from 'react-i18next';
import { Calendar, BarChart2 } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { type NearbyActivity } from '@/services/activity-service';
import { formatDifficultySignal } from '@/constants/sport-levels';
import { getRemainingPlaces } from '@/utils/activity-status';

interface ActivityPopupProps {
  activity: NearbyActivity;
  onPress: () => void;
}

export function ActivityPopup({ activity, onPress }: ActivityPopupProps) {
  const { t, i18n } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const remaining = getRemainingPlaces(activity.max_participants, activity.participant_count);

  return (
    <Pressable style={styles.card} onPress={onPress}>
      {/* Title */}
      <Text style={styles.title} numberOfLines={2}>
        {activity.title}
      </Text>

      {/* Sport label — small colored chip below title */}
      <View style={styles.sportChip}>
        <Text style={styles.sportChipText}>
          {t(`sports.${activity.sport_key}`, activity.sport_key)}
        </Text>
      </View>

      {activity.objective_name && (
        <Text style={styles.objectiveName} numberOfLines={1}>📍 {activity.objective_name}</Text>
      )}

      {/* Date */}
      <View style={styles.row}>
        <Calendar size={12} color={colors.textSecondary} strokeWidth={2} />
        <Text style={styles.value}>
          {dayjs(activity.starts_at).locale(i18n.language).format('ddd D MMM · H[h]mm')}
        </Text>
      </View>

      {/* Difficulty signal — sport-adaptive */}
      {(() => {
        const signal = formatDifficultySignal(activity.sport_key, activity.level, activity.distance_km, activity.elevation_gain_m);
        if (!signal) return null;
        return (
          <>
            <View style={styles.divider} />
            <View style={styles.row}>
              <BarChart2 size={12} color={colors.textSecondary} strokeWidth={2} />
              <Text style={styles.value}>{signal}</Text>
            </View>
          </>
        );
      })()}
    </Pressable>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  card: {
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.md,
    elevation: 8,
    shadowColor: colors.background,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 6,
    borderWidth: 1,
    borderColor: colors.border,
    minWidth: 170,
    gap: spacing.xs,
  },
  sportChip: {
    alignSelf: 'flex-start',
    backgroundColor: colors.cta + '1F',
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 999,
    marginBottom: 2,
  },
  sportChipText: {
    color: colors.cta,
    fontSize: 9,
    fontWeight: '700',
    letterSpacing: 0.6,
    textTransform: 'uppercase',
  },
  title: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: 'bold',
    marginBottom: 2,
  },
  objectiveName: {
    color: colors.textPrimary,
    fontSize: fontSizes.xs,
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
  },
  divider: {
    height: 1,
    backgroundColor: colors.textSecondary,
    opacity: 0.35,
    marginVertical: 2,
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
