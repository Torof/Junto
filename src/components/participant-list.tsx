import { View, Text, Pressable, StyleSheet, Alert } from 'react-native';
import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import * as Burnt from 'burnt';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { participationService } from '@/services/participation-service';

interface ParticipantListProps {
  activityId: string;
  isCreator: boolean;
}

export function ParticipantList({ activityId, isCreator }: ParticipantListProps) {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const [loadingId, setLoadingId] = useState<string | null>(null);

  const { data: participants } = useQuery({
    queryKey: ['participants', activityId],
    queryFn: () => participationService.getForActivity(activityId),
    enabled: isCreator,
    staleTime: 0,
  });

  const pending = (participants ?? []).filter((p) => p.status === 'pending');
  const accepted = (participants ?? []).filter((p) => p.status === 'accepted');

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

  if (!isCreator) return null;

  return (
    <View style={styles.container}>
      {pending.length > 0 && (
        <>
          <Text style={styles.sectionTitle}>{t('participants.pending', { count: pending.length })}</Text>
          {pending.map((p) => (
            <View key={p.participation_id} style={styles.card}>
              <View style={styles.avatar}>
                <Text style={styles.initial}>{p.display_name.charAt(0).toUpperCase()}</Text>
              </View>
              <Text style={styles.name}>{p.display_name}</Text>
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

      {accepted.length > 0 && (
        <>
          <Text style={styles.sectionTitle}>{t('participants.accepted', { count: accepted.length })}</Text>
          {accepted.map((p) => (
            <View key={p.participation_id} style={styles.card}>
              <View style={styles.avatar}>
                <Text style={styles.initial}>{p.display_name.charAt(0).toUpperCase()}</Text>
              </View>
              <Text style={styles.name}>{p.display_name}</Text>
              {isCreator && (
                <Pressable
                  style={[styles.removeBtn, loadingId === p.participation_id && styles.disabled]}
                  onPress={() => {
                    Alert.alert(t('participants.removeConfirm'), p.display_name, [
                      { text: t('activity.no'), style: 'cancel' },
                      { text: t('activity.yes'), style: 'destructive', onPress: () => handleAction(p.participation_id, 'remove') },
                    ]);
                  }}
                  disabled={loadingId === p.participation_id}
                >
                  <Text style={styles.removeBtnText}>✕</Text>
                </Pressable>
              )}
            </View>
          ))}
        </>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { marginTop: spacing.md },
  sectionTitle: { color: colors.textSecondary, fontSize: fontSizes.xs, textTransform: 'uppercase', marginBottom: spacing.sm, marginTop: spacing.md },
  card: { flexDirection: 'row', alignItems: 'center', backgroundColor: colors.surface, borderRadius: radius.md, padding: spacing.sm, marginBottom: spacing.sm },
  avatar: { width: 32, height: 32, borderRadius: 16, backgroundColor: colors.background, alignItems: 'center', justifyContent: 'center', marginRight: spacing.sm },
  initial: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: 'bold' },
  name: { color: colors.textPrimary, fontSize: fontSizes.sm, flex: 1 },
  actions: { flexDirection: 'row', gap: spacing.sm },
  acceptBtn: { backgroundColor: colors.success, width: 32, height: 32, borderRadius: 16, alignItems: 'center', justifyContent: 'center' },
  refuseBtn: { backgroundColor: colors.error, width: 32, height: 32, borderRadius: 16, alignItems: 'center', justifyContent: 'center' },
  removeBtn: { width: 28, height: 28, borderRadius: 14, borderWidth: 1, borderColor: colors.textSecondary, alignItems: 'center', justifyContent: 'center' },
  removeBtnText: { color: colors.textSecondary, fontSize: 12 },
  btnText: { color: colors.textPrimary, fontSize: 16, fontWeight: 'bold' },
  disabled: { opacity: 0.4 },
});
