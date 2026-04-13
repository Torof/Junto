import { View, Text, Pressable, StyleSheet } from 'react-native';
import dayjs from 'dayjs';
import { useTranslation } from 'react-i18next';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { type NearbyActivity } from '@/services/activity-service';
import { UserAvatar } from './user-avatar';
import { getActivityTimeStatus, getStatusColor, getRemainingPlaces } from '@/utils/activity-status';

interface ActivityPopupProps {
  activity: NearbyActivity;
  onViewDetail: () => void;
  onClose: () => void;
}

export function ActivityPopup({ activity, onViewDetail, onClose }: ActivityPopupProps) {
  const { t } = useTranslation();
  const timeStatus = getActivityTimeStatus(activity.starts_at, activity.status);
  const statusColor = getStatusColor(timeStatus);
  const remaining = getRemainingPlaces(activity.max_participants, activity.participant_count);

  return (
    <Pressable style={styles.backdrop} onPress={onClose}>
      <Pressable style={styles.card} onPress={() => {}}>
        <View style={styles.header}>
          <View style={[styles.statusDot, { backgroundColor: statusColor }]} />
          <Text style={styles.sport}>{t(`sports.${activity.sport_key}`, activity.sport_key)}</Text>
        </View>

        <Text style={styles.title} numberOfLines={2}>
          {activity.title}
        </Text>

        <View style={styles.details}>
          <Text style={styles.detail}>
            {dayjs(activity.starts_at).format('ddd D MMM · HH:mm')}
          </Text>
          <Text style={styles.detail}>
            {t('activity.level')}: {activity.level}
          </Text>
          <Text style={styles.detail}>
            {t('activity.places', { remaining, max: activity.max_participants })}
          </Text>
        </View>

        <View style={styles.creator}>
          <UserAvatar name={activity.creator_name} avatarUrl={activity.creator_avatar} size={32} />
          <Text style={styles.creatorName}>{activity.creator_name}</Text>
        </View>

        <Pressable style={styles.button} onPress={onViewDetail}>
          <Text style={styles.buttonText}>{t('activity.viewDetail')}</Text>
        </Pressable>
      </Pressable>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  backdrop: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    top: 0,
    justifyContent: 'flex-end',
  },
  card: {
    backgroundColor: colors.surface,
    borderTopLeftRadius: radius.lg,
    borderTopRightRadius: radius.lg,
    padding: spacing.lg,
    paddingBottom: spacing.xl + 16,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: spacing.sm,
  },
  statusDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
    marginRight: spacing.sm,
  },
  sport: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
    textTransform: 'capitalize',
  },
  title: {
    color: colors.textPrimary,
    fontSize: fontSizes.lg,
    fontWeight: 'bold',
    marginBottom: spacing.md,
  },
  details: {
    marginBottom: spacing.md,
    gap: spacing.xs,
  },
  detail: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
  },
  creator: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    marginBottom: spacing.lg,
  },
  creatorName: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
  },
  button: {
    backgroundColor: colors.cta,
    borderRadius: radius.md,
    paddingVertical: spacing.md,
    alignItems: 'center',
  },
  buttonText: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    fontWeight: 'bold',
  },
});
