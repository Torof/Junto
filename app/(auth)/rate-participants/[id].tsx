import { useState } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet, Alert } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import * as Burnt from 'burnt';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { participationService } from '@/services/participation-service';
import { badgeService, POSITIVE_BADGES, NEGATIVE_BADGES } from '@/services/badge-service';
import { UserAvatar } from '@/components/user-avatar';
import { supabase } from '@/services/supabase';

const ALL_BADGES = [...POSITIVE_BADGES, ...NEGATIVE_BADGES];

export default function RateParticipantsScreen() {
  const { id: activityId } = useLocalSearchParams<{ id: string }>();
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();

  // Selected badges per user: { [userId]: Set<badgeKey> }
  const [selections, setSelections] = useState<Record<string, Set<string>>>({});
  const [isSaving, setIsSaving] = useState(false);

  const { data: currentUserId } = useQuery({
    queryKey: ['currentUser-id'],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id,
  });

  const { data: participants, isLoading } = useQuery({
    queryKey: ['participants', activityId],
    queryFn: () => participationService.getForActivity(activityId ?? ''),
    enabled: !!activityId,
  });

  const others = (participants ?? []).filter(
    (p) => p.status === 'accepted' && p.user_id !== currentUserId,
  );

  const toggleBadge = (userId: string, badgeKey: string) => {
    setSelections((prev) => {
      const userSet = new Set(prev[userId] ?? []);
      if (userSet.has(badgeKey)) userSet.delete(badgeKey);
      else userSet.add(badgeKey);
      return { ...prev, [userId]: userSet };
    });
  };

  const handleSubmit = async () => {
    if (!activityId) return;
    setIsSaving(true);
    try {
      const promises: Promise<void>[] = [];
      for (const [userId, badges] of Object.entries(selections)) {
        for (const badgeKey of badges) {
          promises.push(badgeService.giveReputationBadge(userId, activityId, badgeKey));
        }
      }
      await Promise.all(promises);
      await queryClient.invalidateQueries({ queryKey: ['reputation'] });
      Burnt.toast({ title: t('rate.submitted'), preset: 'done' });
      router.back();
    } catch {
      Alert.alert(t('auth.error'), t('auth.unknownError'));
    } finally {
      setIsSaving(false);
    }
  };

  const hasSelections = Object.values(selections).some((s) => s.size > 0);

  if (isLoading) {
    return (
      <View style={styles.center}>
        <Text style={styles.loadingText}>...</Text>
      </View>
    );
  }

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <Text style={styles.title}>{t('rate.title')}</Text>
      <Text style={styles.subtitle}>{t('rate.subtitle')}</Text>

      {others.map((p) => {
        const userBadges = selections[p.user_id] ?? new Set<string>();
        return (
          <View key={p.user_id} style={styles.participantSection}>
            <View style={styles.participantHeader}>
              <UserAvatar name={p.display_name} avatarUrl={p.avatar_url} size={36} />
              <Text style={styles.participantName}>{p.display_name}</Text>
            </View>

            <Text style={styles.badgeGroupLabel}>{t('rate.positive')}</Text>
            <View style={styles.badgeRow}>
              {POSITIVE_BADGES.map((badge) => (
                <Pressable
                  key={badge.key}
                  style={[styles.badgeChip, userBadges.has(badge.key) && styles.badgeChipSelected]}
                  onPress={() => toggleBadge(p.user_id, badge.key)}
                >
                  <Text style={styles.badgeIcon}>{badge.icon}</Text>
                  <Text style={[styles.badgeLabel, userBadges.has(badge.key) && styles.badgeLabelSelected]}>
                    {t(`badges.${badge.key}`)}
                  </Text>
                </Pressable>
              ))}
            </View>

            <Text style={styles.badgeGroupLabel}>{t('rate.negative')}</Text>
            <View style={styles.badgeRow}>
              {NEGATIVE_BADGES.map((badge) => (
                <Pressable
                  key={badge.key}
                  style={[styles.badgeChip, userBadges.has(badge.key) && styles.badgeChipNegSelected]}
                  onPress={() => toggleBadge(p.user_id, badge.key)}
                >
                  <Text style={styles.badgeIcon}>{badge.icon}</Text>
                  <Text style={[styles.badgeLabel, userBadges.has(badge.key) && styles.badgeLabelNegSelected]}>
                    {t(`badges.${badge.key}`)}
                  </Text>
                </Pressable>
              ))}
            </View>
          </View>
        );
      })}

      <View style={styles.buttonRow}>
        <Pressable
          style={[styles.submitButton, (!hasSelections || isSaving) && styles.buttonDisabled]}
          onPress={handleSubmit}
          disabled={!hasSelections || isSaving}
        >
          <Text style={styles.submitText}>{isSaving ? '...' : t('rate.submit')}</Text>
        </Pressable>
        <Pressable style={styles.skipButton} onPress={() => router.back()}>
          <Text style={styles.skipText}>{t('rate.skip')}</Text>
        </Pressable>
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.lg, paddingBottom: spacing.xl + 32 },
  center: { flex: 1, backgroundColor: colors.background, alignItems: 'center', justifyContent: 'center' },
  loadingText: { color: colors.textSecondary, fontSize: fontSizes.lg },
  title: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold', marginBottom: spacing.xs },
  subtitle: { color: colors.textSecondary, fontSize: fontSizes.sm, marginBottom: spacing.xl },
  participantSection: { marginBottom: spacing.xl },
  participantHeader: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, marginBottom: spacing.md },
  participantName: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
  badgeGroupLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, textTransform: 'uppercase', marginBottom: spacing.sm, marginTop: spacing.sm },
  badgeRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs },
  badgeChip: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.xs,
    backgroundColor: colors.surface, borderRadius: radius.full,
    paddingHorizontal: spacing.sm, paddingVertical: spacing.xs,
  },
  badgeChipSelected: { backgroundColor: colors.success + '30', borderWidth: 1, borderColor: colors.success },
  badgeChipNegSelected: { backgroundColor: colors.error + '20', borderWidth: 1, borderColor: colors.error },
  badgeIcon: { fontSize: 14 },
  badgeLabel: { color: colors.textSecondary, fontSize: fontSizes.xs },
  badgeLabelSelected: { color: colors.success, fontWeight: 'bold' },
  badgeLabelNegSelected: { color: colors.error, fontWeight: 'bold' },
  buttonRow: { marginTop: spacing.lg, gap: spacing.sm },
  submitButton: { backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center' },
  buttonDisabled: { opacity: 0.4 },
  submitText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
  skipButton: { paddingVertical: spacing.sm, alignItems: 'center' },
  skipText: { color: colors.textSecondary, fontSize: fontSizes.sm },
});
