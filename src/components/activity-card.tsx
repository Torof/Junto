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
        <Text style={styles.sport} numberOfLines={1}>{t(`sports.${activity.sport_key}`, activity.sport_key)}</Text>
        <Text style={styles.time}>{dayjs(activity.starts_at).locale(i18n.language).format('ddd D MMM · HH:mm')}</Text>
      </View>

      <Text style={styles.title} numberOfLines={1}>
        {activity.title}
      </Text>

      <View style={styles.bottom}>
        <Text style={styles.level} numberOfLines={1}>{activity.level}</Text>
        <Text style={styles.places} numberOfLines={1}>
          {t('activity.places', { remaining, max: activity.max_participants })}
        </Text>
        {distanceKm !== undefined && (
          <Text style={styles.distance} numberOfLines={1}>{distanceKm.toFixed(1)} km</Text>
        )}
        <Text style={styles.creator} numberOfLines={1}>{activity.creator_name}</Text>
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
    flexShrink: 1,
  },
  time: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    marginLeft: 'auto',
    flexShrink: 0,
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
    gap: spacing.sm,
  },
  level: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    flexShrink: 0,
  },
  places: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    flexShrink: 0,
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
    flexShrink: 1,
  },
});
