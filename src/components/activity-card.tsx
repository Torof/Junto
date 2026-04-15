import { View, Text, Pressable, StyleSheet } from 'react-native';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { useTranslation } from 'react-i18next';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { type NearbyActivity } from '@/services/activity-service';
import { getActivityTimeStatus, getStatusColor, getRemainingPlaces } from '@/utils/activity-status';

interface ActivityCardProps {
  activity: NearbyActivity;
  onPress: () => void;
  distanceKm?: number;
}

export function ActivityCard({ activity, onPress, distanceKm }: ActivityCardProps) {
  const { t, i18n } = useTranslation();
  const timeStatus = getActivityTimeStatus(activity.starts_at, activity.status);
  const statusColor = getStatusColor(timeStatus);
  const remaining = getRemainingPlaces(activity.max_participants, activity.participant_count);

  return (
    <Pressable style={styles.card} onPress={onPress}>
      <View style={styles.top}>
        <View style={[styles.statusDot, { backgroundColor: statusColor }]} />
        <Text style={styles.sport}>{t(`sports.${activity.sport_key}`, activity.sport_key)}</Text>
        <Text style={styles.time}>{dayjs(activity.starts_at).locale(i18n.language).format('ddd D MMM · HH:mm')}</Text>
      </View>

      <Text style={styles.title} numberOfLines={1}>
        {activity.title}
      </Text>

      <View style={styles.bottom}>
        <Text style={styles.level}>{activity.level}</Text>
        <Text style={styles.places}>
          {t('activity.places', { remaining, max: activity.max_participants })}
        </Text>
        {distanceKm !== undefined && (
          <Text style={styles.distance}>{distanceKm.toFixed(1)} km</Text>
        )}
        <Text style={styles.creator}>{activity.creator_name}</Text>
      </View>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    padding: spacing.md,
    marginBottom: spacing.sm,
  },
  top: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: spacing.xs,
    gap: spacing.sm,
  },
  statusDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  sport: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    textTransform: 'capitalize',
  },
  time: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    marginLeft: 'auto',
  },
  title: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    fontWeight: 'bold',
    marginBottom: spacing.sm,
  },
  bottom: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
  },
  level: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
  },
  places: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
  },
  distance: {
    color: colors.cta,
    fontSize: fontSizes.xs,
    fontWeight: 'bold',
  },
  creator: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    marginLeft: 'auto',
  },
});
