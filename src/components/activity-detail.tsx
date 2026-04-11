import { View, Text, ScrollView, Pressable, StyleSheet } from 'react-native';
import dayjs from 'dayjs';
import { useTranslation } from 'react-i18next';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { type NearbyActivity } from '@/services/activity-service';
import { getActivityTimeStatus, getStatusColor, getRemainingPlaces } from '@/utils/activity-status';

interface ActivityDetailProps {
  activity: NearbyActivity;
  onJoin?: () => void;
  joinLabel: string;
}

export function ActivityDetail({ activity, onJoin, joinLabel }: ActivityDetailProps) {
  const { t } = useTranslation();
  const timeStatus = getActivityTimeStatus(activity.starts_at, activity.status);
  const statusColor = getStatusColor(timeStatus);
  const remaining = getRemainingPlaces(activity.max_participants, activity.participant_count);

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <View style={styles.header}>
        <View style={[styles.statusBadge, { backgroundColor: statusColor }]}>
          <Text style={styles.statusText}>{t(`activity.status.${timeStatus}`)}</Text>
        </View>
        <Text style={styles.sport}>{t(`sports.${activity.sport_key}`, activity.sport_key)}</Text>
      </View>

      <Text style={styles.title}>{activity.title}</Text>

      <View style={styles.infoGrid}>
        <View style={styles.infoRow}>
          <Text style={styles.infoLabel}>{t('activity.level')}</Text>
          <Text style={styles.infoValue}>{activity.level}</Text>
        </View>
        <View style={styles.infoRow}>
          <Text style={styles.infoLabel}>{dayjs(activity.starts_at).format('ddd D MMM')}</Text>
          <Text style={styles.infoValue}>{dayjs(activity.starts_at).format('HH:mm')}</Text>
        </View>
        <View style={styles.infoRow}>
          <Text style={styles.infoLabel}>{t('activity.duration')}</Text>
          <Text style={styles.infoValue}>{activity.duration}</Text>
        </View>
        <View style={styles.infoRow}>
          <Text style={styles.infoLabel}>{t('activity.places', { remaining, max: activity.max_participants })}</Text>
          <Text style={styles.infoValue}>{activity.participant_count}/{activity.max_participants}</Text>
        </View>
      </View>

      {activity.description && (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>{t('activity.description')}</Text>
          <Text style={styles.description}>{activity.description}</Text>
        </View>
      )}

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>{t('activity.creator')}</Text>
        <View style={styles.creator}>
          <View style={styles.creatorAvatar}>
            <Text style={styles.creatorInitial}>
              {activity.creator_name.charAt(0).toUpperCase()}
            </Text>
          </View>
          <Text style={styles.creatorName}>{activity.creator_name}</Text>
        </View>
      </View>

      {onJoin && remaining > 0 && (
        <Pressable style={styles.joinButton} onPress={onJoin}>
          <Text style={styles.joinText}>{joinLabel}</Text>
        </Pressable>
      )}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  content: {
    padding: spacing.lg,
    paddingBottom: spacing.xl + 32,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: spacing.md,
    gap: spacing.sm,
  },
  statusBadge: {
    paddingHorizontal: spacing.sm,
    paddingVertical: spacing.xs,
    borderRadius: radius.full,
  },
  statusText: {
    color: colors.textPrimary,
    fontSize: fontSizes.xs,
    fontWeight: 'bold',
  },
  sport: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
    textTransform: 'capitalize',
  },
  title: {
    color: colors.textPrimary,
    fontSize: fontSizes.xl,
    fontWeight: 'bold',
    marginBottom: spacing.lg,
  },
  infoGrid: {
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    padding: spacing.md,
    marginBottom: spacing.lg,
    gap: spacing.sm,
  },
  infoRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  infoLabel: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
  },
  infoValue: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: 'bold',
  },
  section: {
    marginBottom: spacing.lg,
  },
  sectionTitle: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
    marginBottom: spacing.sm,
    textTransform: 'uppercase',
  },
  description: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    lineHeight: 22,
  },
  creator: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  creatorAvatar: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: colors.surface,
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: spacing.sm,
  },
  creatorInitial: {
    color: colors.cta,
    fontSize: fontSizes.md,
    fontWeight: 'bold',
  },
  creatorName: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
  },
  joinButton: {
    backgroundColor: colors.cta,
    borderRadius: radius.md,
    paddingVertical: spacing.md,
    alignItems: 'center',
    marginTop: spacing.md,
  },
  joinText: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    fontWeight: 'bold',
  },
});
