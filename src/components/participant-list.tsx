import { View, Text, Pressable, StyleSheet, Alert } from 'react-native';
import { useState, useMemo } from 'react';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import * as Burnt from 'burnt';
import { Check } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import { participationService } from '@/services/participation-service';
import { UserAvatar } from './user-avatar';
import { ReliabilityRing } from './reliability-ring';
import { haptic } from '@/lib/haptics';
import { getFriendlyError } from '@/utils/friendly-error';
import type { AppColors } from '@/constants/colors';

interface ParticipantListProps {
  activityId: string;
  activityTitle?: string;
  isCreator: boolean;
  creatorId: string;
  creatorName: string;
  creatorAvatar?: string | null;
  onProfilePress?: (userId: string) => void;
}

export function ParticipantList({ activityId, activityTitle, isCreator, creatorId, creatorName, creatorAvatar, onProfilePress }: ParticipantListProps) {
  const { t } = useTranslation();
  const colors = useColors();
  const router = useRouter();
  const queryClient = useQueryClient();
  const [loadingId, setLoadingId] = useState<string | null>(null);
  const styles = useMemo(() => createStyles(colors), [colors]);

  const { data: accepted } = useQuery({
    queryKey: ['participants', activityId],
    queryFn: () => participationService.getForActivity(activityId),
    staleTime: 0,
  });

  const { data: pending } = useQuery({
    queryKey: ['participants-pending', activityId],
    queryFn: () => participationService.getPendingForActivity(activityId),
    enabled: isCreator,
    staleTime: 0,
  });

  const { data: lateLeavers } = useQuery({
    queryKey: ['participants-late-leavers', activityId],
    queryFn: () => participationService.getLateLeaversForCreator(activityId),
    enabled: isCreator,
    staleTime: 0,
  });

  const handleWaive = async (participationId: string) => {
    setLoadingId(participationId);
    try {
      await participationService.waivePenalty(participationId);
      await queryClient.invalidateQueries({ queryKey: ['participants-late-leavers', activityId] });
      Burnt.toast({ title: t('participants.penaltyWaived'), preset: 'done' });
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
    } finally {
      setLoadingId(null);
    }
  };

  // Filter out creator from accepted list (shown separately above)
  const otherAccepted = (accepted ?? []).filter((p) => p.user_id !== creatorId);
  const creatorRow = (accepted ?? []).find((p) => p.user_id === creatorId);
  const creatorPresent = creatorRow?.confirmed_present === true;

  const handleAction = async (participationId: string, action: 'accept' | 'refuse' | 'remove') => {
    setLoadingId(participationId);
    try {
      if (action === 'accept') await participationService.accept(participationId);
      else if (action === 'refuse') await participationService.refuse(participationId);
      else await participationService.remove(participationId);

      await queryClient.refetchQueries({ queryKey: ['participants', activityId] });
      await queryClient.invalidateQueries({ queryKey: ['activities'] });
      const toastKey = action === 'accept' ? 'toast.participantAccepted'
        : action === 'refuse' ? 'toast.participantRefused'
        : 'toast.participantRemoved';
      Burnt.toast({ title: t(toastKey), preset: action === 'accept' ? 'done' : undefined });
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
    } finally {
      setLoadingId(null);
    }
  };

  return (
    <View style={styles.container}>
      <Text style={styles.sectionTitle}>{t('participants.title')}</Text>

      <View style={styles.avatarRow}>
        {/* Creator — always first, marked with the orange organizer tick. */}
        <Pressable style={styles.avatarItem} onPress={() => onProfilePress ? onProfilePress(creatorId) : router.push(`/(auth)/profile/${creatorId}`)}>
          <UserAvatar
            name={creatorName}
            avatarUrl={creatorAvatar}
            size={44}
            confirmedPresent={creatorPresent}
            isOrganizer
          />
        </Pressable>

        {/* Accepted participants (excluding creator) */}
        {otherAccepted.map((p) => (
          <Pressable key={p.participation_id} style={styles.avatarItem} onPress={() => onProfilePress ? onProfilePress(p.user_id) : router.push(`/(auth)/profile/${p.user_id}`)}>
            <UserAvatar name={p.display_name} avatarUrl={p.avatar_url} size={44} confirmedPresent={p.confirmed_present === true} />
          </Pressable>
        ))}
      </View>

      {/* Pending requests (creator only) — separate section */}
      {isCreator && (pending ?? []).length > 0 && (
        <View style={styles.pendingBlock}>
          <Text style={styles.subTitle}>{t('participants.pending', { count: (pending ?? []).length })}</Text>
          {(pending ?? []).map((p) => (
            <Pressable
              key={p.participation_id}
              style={styles.pendingRow}
              onPress={() => onProfilePress ? onProfilePress(p.user_id) : router.push(`/(auth)/profile/${p.user_id}?participation=${p.participation_id}&activityTitle=${encodeURIComponent(activityTitle ?? '')}`)}
            >
              <ReliabilityRing tier={p.reliability_tier ?? null} size={36} strokeWidth={3} showLabel={false}>
                <UserAvatar name={p.display_name} avatarUrl={p.avatar_url} size={36} />
              </ReliabilityRing>
              <Text style={styles.pendingName} numberOfLines={1}>{p.display_name}</Text>
              <View style={styles.actions}>
                <Pressable
                  style={[styles.acceptBtn, loadingId === p.participation_id && styles.disabled]}
                  onPress={(e) => { e.stopPropagation(); haptic.success(); handleAction(p.participation_id, 'accept'); }}
                  disabled={loadingId === p.participation_id}
                  accessibilityLabel={t('participants.accept')}
                >
                  <Text style={styles.btnText}>✓</Text>
                </Pressable>
                <Pressable
                  style={[styles.refuseBtn, loadingId === p.participation_id && styles.disabled]}
                  onPress={(e) => { e.stopPropagation(); haptic.light(); handleAction(p.participation_id, 'refuse'); }}
                  disabled={loadingId === p.participation_id}
                  accessibilityLabel={t('participants.refuse')}
                >
                  <Text style={styles.btnText}>✕</Text>
                </Pressable>
              </View>
            </Pressable>
          ))}
        </View>
      )}

      {/* Late leavers (creator only) — separate section */}
      {isCreator && (lateLeavers ?? []).length > 0 && (
        <View style={styles.lateLeaversBlock}>
          <Text style={styles.subTitle}>{t('participants.lateLeavers')}</Text>
          {(lateLeavers ?? []).map((p) => (
            <View key={p.participation_id} style={styles.pendingRow}>
              <UserAvatar name={p.display_name} avatarUrl={p.avatar_url} size={32} />
              <View style={styles.lateLeaverInfo}>
                <Text style={styles.pendingName}>{p.display_name}</Text>
                {p.left_reason && (
                  <Text style={styles.lateLeaverReason} numberOfLines={2}>{p.left_reason}</Text>
                )}
              </View>
              {p.penalty_waived ? (
                <Text style={styles.waivedTag}>{t('participants.penaltyWaivedTag')}</Text>
              ) : (
                <Pressable
                  style={[styles.waiveBtn, loadingId === p.participation_id && styles.disabled]}
                  onPress={() => handleWaive(p.participation_id)}
                  disabled={loadingId === p.participation_id}
                >
                  <Text style={styles.waiveBtnText}>{t('participants.waive')}</Text>
                </Pressable>
              )}
            </View>
          ))}
        </View>
      )}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { marginTop: spacing.md },
  sectionTitle: { color: colors.textSecondary, fontSize: fontSizes.xs, textTransform: 'uppercase', marginBottom: spacing.sm },
  avatarRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.md, marginBottom: spacing.md },
  avatarItem: { alignItems: 'center' },
  organizerPill: { backgroundColor: colors.cta, borderRadius: radius.full, paddingHorizontal: spacing.xs, paddingVertical: 1, marginTop: -6 },
  presentBadge: {
    position: 'absolute',
    bottom: -2,
    right: -2,
    width: 18,
    height: 18,
    borderRadius: 9,
    backgroundColor: colors.success,
    borderWidth: 2,
    borderColor: colors.surface,
    alignItems: 'center',
    justifyContent: 'center',
  },
  organizerPillText: { color: colors.textPrimary, fontSize: fontSizes.xs, fontWeight: 'bold' },
  subTitle: { color: colors.textSecondary, fontSize: fontSizes.xs, textTransform: 'uppercase', marginBottom: spacing.sm, marginTop: spacing.sm },
  pendingRow: {
    flexDirection: 'row', alignItems: 'center',
    backgroundColor: colors.surface, borderRadius: radius.md,
    paddingHorizontal: spacing.sm, paddingVertical: spacing.xs,
    marginBottom: spacing.xs, gap: spacing.sm,
  },
  pendingName: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600', flex: 1 },
  pendingSports: { fontSize: 13 },
  actions: { flexDirection: 'row', gap: spacing.sm },
  acceptBtn: { backgroundColor: colors.success, width: 44, height: 44, borderRadius: 22, alignItems: 'center', justifyContent: 'center' },
  refuseBtn: { backgroundColor: colors.error, width: 44, height: 44, borderRadius: 22, alignItems: 'center', justifyContent: 'center' },
  btnText: { color: colors.textPrimary, fontSize: 18, fontWeight: 'bold' },
  disabled: { opacity: 0.4 },
  pendingBlock: { gap: spacing.xs, marginTop: spacing.md },
  lateLeaversBlock: { gap: spacing.xs, marginTop: spacing.md },
  lateLeaverInfo: { flex: 1, marginLeft: spacing.sm, gap: 2 },
  lateLeaverReason: { color: colors.textSecondary, fontSize: fontSizes.xs, fontStyle: 'italic' },
  waiveBtn: {
    backgroundColor: 'transparent', borderWidth: 1, borderColor: colors.cta,
    borderRadius: radius.full, paddingHorizontal: spacing.sm, paddingVertical: 4,
  },
  waiveBtnText: { color: colors.cta, fontSize: fontSizes.xs, fontWeight: 'bold' },
  waivedTag: { color: colors.success, fontSize: fontSizes.xs, fontStyle: 'italic' },
});
