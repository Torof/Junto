import { View, Text, Pressable, StyleSheet, Alert } from 'react-native';
import { useState } from 'react';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import * as Burnt from 'burnt';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { participationService } from '@/services/participation-service';
import { UserAvatar } from './user-avatar';

interface ParticipantListProps {
  activityId: string;
  isCreator: boolean;
  creatorId: string;
  creatorName: string;
  creatorAvatar?: string | null;
}

export function ParticipantList({ activityId, isCreator, creatorId, creatorName, creatorAvatar }: ParticipantListProps) {
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const [loadingId, setLoadingId] = useState<string | null>(null);

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

  // Filter out creator from accepted list (shown separately above)
  const otherAccepted = (accepted ?? []).filter((p) => p.user_id !== creatorId);

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
      Alert.alert(t('auth.error'), err instanceof Error ? err.message : t('auth.unknownError'));
    } finally {
      setLoadingId(null);
    }
  };

  return (
    <View style={styles.container}>
      <Text style={styles.sectionTitle}>{t('participants.title')}</Text>

      <View style={styles.avatarRow}>
        {/* Creator — always first */}
        <Pressable style={styles.avatarItem} onPress={() => router.push(`/(auth)/profile/${creatorId}`)}>
          <UserAvatar name={creatorName} avatarUrl={creatorAvatar} size={44} />
          <View style={styles.organizerPill}>
            <Text style={styles.organizerPillText}>{t('participants.organizer')}</Text>
          </View>
        </Pressable>

      {/* Pending requests (creator only) */}
      {isCreator && (pending ?? []).length > 0 && (
        <>
          <Text style={styles.subTitle}>{t('participants.pending', { count: (pending ?? []).length })}</Text>
          {(pending ?? []).map((p) => (
            <View key={p.participation_id} style={styles.pendingCard}>
              <Pressable style={styles.pendingProfileLink} onPress={() => router.push(`/(auth)/profile/${p.user_id}`)}>
                <UserAvatar name={p.display_name} avatarUrl={p.avatar_url} size={32} />
                <Text style={styles.pendingName}>{p.display_name}</Text>
              </Pressable>
              <View style={styles.actions}>
                <Pressable
                  style={[styles.acceptBtn, loadingId === p.participation_id && styles.disabled]}
                  onPress={() => handleAction(p.participation_id, 'accept')}
                  disabled={loadingId === p.participation_id}
                >
                  <Text style={styles.btnText}>✓</Text>
                </Pressable>
                <Pressable
                  style={[styles.refuseBtn, loadingId === p.participation_id && styles.disabled]}
                  onPress={() => handleAction(p.participation_id, 'refuse')}
                  disabled={loadingId === p.participation_id}
                >
                  <Text style={styles.btnText}>✕</Text>
                </Pressable>
              </View>
            </View>
          ))}
        </>
      )}

        {/* Accepted participants (excluding creator) */}
        {otherAccepted.map((p) => (
          <Pressable key={p.participation_id} style={styles.avatarItem} onPress={() => router.push(`/(auth)/profile/${p.user_id}`)}>
            <UserAvatar name={p.display_name} avatarUrl={p.avatar_url} size={44} />
          </Pressable>
        ))}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { marginTop: spacing.md },
  sectionTitle: { color: colors.textSecondary, fontSize: fontSizes.xs, textTransform: 'uppercase', marginBottom: spacing.sm },
  avatarRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.md, marginBottom: spacing.md },
  avatarItem: { alignItems: 'center' },
  organizerPill: { backgroundColor: colors.cta, borderRadius: radius.full, paddingHorizontal: spacing.xs, paddingVertical: 1, marginTop: -6 },
  organizerPillText: { color: '#fff', fontSize: fontSizes.xs - 2, fontWeight: 'bold' },
  subTitle: { color: colors.textSecondary, fontSize: fontSizes.xs, textTransform: 'uppercase', marginBottom: spacing.sm, marginTop: spacing.sm },
  pendingCard: { flexDirection: 'row', alignItems: 'center', backgroundColor: colors.surface, borderRadius: radius.md, padding: spacing.sm, marginBottom: spacing.sm },
  pendingProfileLink: { flexDirection: 'row', alignItems: 'center', flex: 1 },
  pendingName: { color: colors.textPrimary, fontSize: fontSizes.sm, flex: 1 },
  actions: { flexDirection: 'row', gap: spacing.sm },
  acceptBtn: { backgroundColor: colors.success, width: 32, height: 32, borderRadius: 16, alignItems: 'center', justifyContent: 'center' },
  refuseBtn: { backgroundColor: colors.error, width: 32, height: 32, borderRadius: 16, alignItems: 'center', justifyContent: 'center' },
  btnText: { color: colors.textPrimary, fontSize: 16, fontWeight: 'bold' },
  disabled: { opacity: 0.4 },
});
