import { View, Text, StyleSheet } from 'react-native';
import dayjs from 'dayjs';
import { colors, fontSizes, spacing } from '@/constants/theme';
import { getActivityTimeStatus, getStatusColor, getRemainingPlaces } from '@/utils/activity-status';
import { type NearbyActivity } from '@/services/activity-service';

interface ActivityPinProps {
  activity: NearbyActivity;
}

export function ActivityPin({ activity }: ActivityPinProps) {
  const timeStatus = getActivityTimeStatus(activity.starts_at, activity.status);
  const statusColor = getStatusColor(timeStatus);
  const remaining = getRemainingPlaces(activity.max_participants, activity.participant_count);
  const time = dayjs(activity.starts_at).format('HH:mm');

  return (
    <View style={[styles.container, { borderColor: statusColor }]}>
      <View style={[styles.dot, { backgroundColor: statusColor }]} />
      <Text style={styles.time} numberOfLines={1}>
        {time}
      </Text>
      <Text style={styles.places} numberOfLines={1}>
        {remaining}/{activity.max_participants}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    backgroundColor: colors.background,
    borderRadius: 12,
    borderWidth: 2,
    paddingHorizontal: spacing.sm,
    paddingVertical: spacing.xs,
    alignItems: 'center',
    minWidth: 48,
  },
  dot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    marginBottom: 2,
  },
  time: {
    color: colors.textPrimary,
    fontSize: fontSizes.xs,
    fontWeight: 'bold',
  },
  places: {
    color: colors.textSecondary,
    fontSize: 10,
  },
});
