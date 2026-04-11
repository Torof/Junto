import { View, Text, ScrollView, Pressable, StyleSheet, Alert, Share } from 'react-native';
import { useState } from 'react';
import { useRouter } from 'expo-router';
import dayjs from 'dayjs';
import { useTranslation } from 'react-i18next';
import { useQueryClient } from '@tanstack/react-query';
import * as Burnt from 'burnt';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { activityService, type NearbyActivity } from '@/services/activity-service';
import { participationService, type Participation } from '@/services/participation-service';
import { getActivityTimeStatus, getStatusColor, getRemainingPlaces } from '@/utils/activity-status';
import { getSportIcon } from '@/constants/sport-icons';
import { ParticipantList } from './participant-list';
import { ActivityWall } from './activity-wall';

interface ActivityDetailProps {
  activity: NearbyActivity;
  participation: Participation | null;
  isCreator: boolean;
  isAuthenticated: boolean;
  onJoinRedirect?: () => void;
}

export function ActivityDetail({
  activity,
  participation,
  isCreator,
  isAuthenticated,
  onJoinRedirect,
}: ActivityDetailProps) {
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const [isLoading, setIsLoading] = useState(false);

  const timeStatus = getActivityTimeStatus(activity.starts_at, activity.status);
  const statusColor = getStatusColor(timeStatus);
  const remaining = getRemainingPlaces(activity.max_participants, activity.participant_count);

  const handleJoin = async () => {
    if (!isAuthenticated) {
      onJoinRedirect?.();
      return;
    }
    setIsLoading(true);
    try {
      await participationService.join(activity.id);
      await queryClient.refetchQueries({ queryKey: ['participation', activity.id] });
      await queryClient.refetchQueries({ queryKey: ['activity', activity.id] });
      await queryClient.invalidateQueries({ queryKey: ['activities'] });
      const isApproval = activity.visibility === 'approval' || activity.visibility === 'private_link_approval';
      Burnt.toast({ title: t(isApproval ? 'toast.requestSent' : 'toast.joinedActivity'), preset: 'done' });
    } catch (err) {
      Alert.alert(t('auth.error'), err instanceof Error ? err.message : t('auth.unknownError'));
    } finally {
      setIsLoading(false);
    }
  };

  const handleLeave = async () => {
    setIsLoading(true);
    try {
      await participationService.leave(activity.id);
      await queryClient.invalidateQueries({ queryKey: ['participation', activity.id] });
      await queryClient.invalidateQueries({ queryKey: ['activity', activity.id] });
      await queryClient.invalidateQueries({ queryKey: ['activities'] });
      Burnt.toast({ title: t('toast.leftActivity') });
    } catch (err) {
      Alert.alert(t('auth.error'), err instanceof Error ? err.message : t('auth.unknownError'));
    } finally {
      setIsLoading(false);
    }
  };

  const handleCancel = async () => {
    Alert.alert(t('activity.cancelConfirmTitle'), t('activity.cancelConfirmMessage'), [
      { text: t('activity.no'), style: 'cancel' },
      {
        text: t('activity.yes'),
        style: 'destructive',
        onPress: async () => {
          setIsLoading(true);
          try {
            await participationService.cancel(activity.id);
            await queryClient.invalidateQueries({ queryKey: ['activities'] });
            Burnt.toast({ title: t('toast.activityCancelled') });
          } catch (err) {
            Alert.alert(t('auth.error'), err instanceof Error ? err.message : t('auth.unknownError'));
          } finally {
            setIsLoading(false);
          }
        },
      },
    ]);
  };

  const handleShare = async () => {
    try {
      const token = await activityService.getInviteToken(activity.id);
      if (!token) return;
      const link = `junto://invite/${token}`;
      await Share.share({
        message: `${activity.title} — ${link}`,
      });
    } catch {
      // User cancelled share — do nothing
    }
  };

  const canRejoin = participation && ['withdrawn', 'refused'].includes(participation.status);
  const showJoinButton = !isCreator && (!participation || canRejoin) && remaining > 0 && activity.status !== 'cancelled';
  const showLeaveButton = !isCreator && participation && ['accepted', 'pending'].includes(participation.status);
  const showCancelButton = isCreator && ['published', 'in_progress'].includes(activity.status);
  const isPending = participation?.status === 'pending';
  const isAccepted = participation?.status === 'accepted';

  const joinLabel = activity.visibility === 'approval' || activity.visibility === 'private_link_approval'
    ? t('activity.requestJoin')
    : t('activity.join');

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <View style={styles.header}>
        <View style={[styles.statusBadge, { backgroundColor: statusColor }]}>
          <Text style={styles.statusText}>{t(`activity.status.${timeStatus}`)}</Text>
        </View>
        <Text style={styles.sportIcon}>{getSportIcon(activity.sport_key)}</Text>
        <Text style={styles.sport}>{t(`sports.${activity.sport_key}`, activity.sport_key)}</Text>
      </View>

      <Text style={styles.title}>{activity.title}</Text>

      {isPending && (
        <View style={styles.pendingBanner}>
          <Text style={styles.pendingText}>{t('activity.pendingRequest')}</Text>
        </View>
      )}

      {isAccepted && !isCreator && (
        <View style={styles.acceptedBanner}>
          <Text style={styles.acceptedText}>{t('activity.youAreIn')}</Text>
        </View>
      )}

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

      {activity.description ? (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>{t('activity.description')}</Text>
          <Text style={styles.description}>{activity.description}</Text>
        </View>
      ) : null}

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>{t('activity.creator')}</Text>
        <Pressable style={styles.creator} onPress={() => router.push(`/(auth)/profile/${activity.creator_id}`)}>
          <View style={styles.creatorAvatar}>
            <Text style={styles.creatorInitial}>{activity.creator_name.charAt(0).toUpperCase()}</Text>
          </View>
          <Text style={styles.creatorName}>{activity.creator_name}</Text>
        </Pressable>
      </View>

      <ParticipantList activityId={activity.id} isCreator={isCreator} />

      {(isCreator || isAccepted) && (
        <ActivityWall
          activityId={activity.id}
          isActive={['published', 'in_progress'].includes(activity.status)}
        />
      )}

      {showJoinButton && (
        <Pressable
          style={[styles.joinButton, isLoading && styles.buttonDisabled]}
          onPress={handleJoin}
          disabled={isLoading}
        >
          <Text style={styles.buttonText}>{isLoading ? '...' : joinLabel}</Text>
        </Pressable>
      )}

      {showLeaveButton && (
        <Pressable
          style={[styles.leaveButton, isLoading && styles.buttonDisabled]}
          onPress={handleLeave}
          disabled={isLoading}
        >
          <Text style={styles.buttonText}>{isLoading ? '...' : t('activity.leave')}</Text>
        </Pressable>
      )}

      {showCancelButton && (
        <Pressable
          style={[styles.cancelButton, isLoading && styles.buttonDisabled]}
          onPress={handleCancel}
          disabled={isLoading}
        >
          <Text style={styles.buttonText}>{isLoading ? '...' : t('activity.cancel')}</Text>
        </Pressable>
      )}

      {isCreator && ['published', 'in_progress'].includes(activity.status) && (
        <Pressable style={styles.editButton} onPress={() => router.push(`/(auth)/edit/${activity.id}`)}>
          <Text style={styles.editText}>{t('activity.edit')}</Text>
        </Pressable>
      )}

      {isCreator && (
        <Pressable style={styles.shareButton} onPress={handleShare}>
          <Text style={styles.shareText}>{t('activity.shareLink')}</Text>
        </Pressable>
      )}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.lg, paddingBottom: spacing.xl + 32 },
  header: { flexDirection: 'row', alignItems: 'center', marginBottom: spacing.md, gap: spacing.sm },
  statusBadge: { paddingHorizontal: spacing.sm, paddingVertical: spacing.xs, borderRadius: radius.full },
  statusText: { color: colors.textPrimary, fontSize: fontSizes.xs, fontWeight: 'bold' },
  sportIcon: { fontSize: 20 },
  sport: { color: colors.textSecondary, fontSize: fontSizes.sm, textTransform: 'capitalize' },
  title: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold', marginBottom: spacing.md },
  pendingBanner: { backgroundColor: colors.warning + '20', borderRadius: radius.md, padding: spacing.md, marginBottom: spacing.md },
  pendingText: { color: colors.warning, fontSize: fontSizes.sm, fontWeight: 'bold', textAlign: 'center' },
  acceptedBanner: { backgroundColor: colors.success + '20', borderRadius: radius.md, padding: spacing.md, marginBottom: spacing.md },
  acceptedText: { color: colors.success, fontSize: fontSizes.sm, fontWeight: 'bold', textAlign: 'center' },
  infoGrid: { backgroundColor: colors.surface, borderRadius: radius.md, padding: spacing.md, marginBottom: spacing.lg, gap: spacing.sm },
  infoRow: { flexDirection: 'row', justifyContent: 'space-between' },
  infoLabel: { color: colors.textSecondary, fontSize: fontSizes.sm },
  infoValue: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: 'bold' },
  section: { marginBottom: spacing.lg },
  sectionTitle: { color: colors.textSecondary, fontSize: fontSizes.xs, marginBottom: spacing.sm, textTransform: 'uppercase' },
  description: { color: colors.textPrimary, fontSize: fontSizes.md, lineHeight: 22 },
  creator: { flexDirection: 'row', alignItems: 'center' },
  creatorAvatar: { width: 40, height: 40, borderRadius: 20, backgroundColor: colors.surface, alignItems: 'center', justifyContent: 'center', marginRight: spacing.sm },
  creatorInitial: { color: colors.cta, fontSize: fontSizes.md, fontWeight: 'bold' },
  creatorName: { color: colors.textPrimary, fontSize: fontSizes.md },
  joinButton: { backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.md },
  leaveButton: { backgroundColor: colors.surface, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.md, borderWidth: 1, borderColor: colors.textSecondary },
  cancelButton: { backgroundColor: colors.error, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.md },
  buttonDisabled: { opacity: 0.4 },
  buttonText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
  editButton: { backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.md },
  editText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: 'bold' },
  shareButton: { backgroundColor: colors.surface, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.md, borderWidth: 1, borderColor: colors.cta },
  shareText: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: 'bold' },
});
