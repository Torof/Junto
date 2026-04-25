import { useEffect, useState, useMemo } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet, Alert } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import * as Burnt from 'burnt';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { participationService } from '@/services/participation-service';
import { badgeService, POSITIVE_BADGES, NEGATIVE_BADGES } from '@/services/badge-service';
import { endorsementService } from '@/services/endorsement-service';
import { activityService } from '@/services/activity-service';
import { UserAvatar } from '@/components/user-avatar';
import { LogoSpinner } from '@/components/logo-spinner';
import { supabase } from '@/services/supabase';
import { getFriendlyError } from '@/utils/friendly-error';

// level_accurate is replaced by per-sport endorsements — hide from the rating flow.
const DISPLAYED_POSITIVE_BADGES = POSITIVE_BADGES.filter((b) => b.key !== 'level_accurate');

export default function RateParticipantsScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { id: activityId } = useLocalSearchParams<{ id: string }>();
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();

  // Selected badges per user: { [userId]: Set<badgeKey> }
  const [selections, setSelections] = useState<Record<string, Set<string>>>({});
  // Sport level endorsement per user: true=confirm, false=contest, undefined=skip
  const [endorsements, setEndorsements] = useState<Record<string, boolean>>({});
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

  const { data: activity } = useQuery({
    queryKey: ['activity', activityId],
    queryFn: () => activityService.getById(activityId ?? ''),
    enabled: !!activityId,
  });

  const { data: myEndorsements } = useQuery({
    queryKey: ['my-endorsements', activityId],
    queryFn: () => endorsementService.getMyVotesForActivity(activityId ?? ''),
    enabled: !!activityId,
  });

  const { data: existingVotes, isLoading: votesLoading } = useQuery({
    queryKey: ['my-votes', activityId],
    queryFn: async () => {
      if (!activityId || !currentUserId) return [] as { voted_id: string }[];
      const { data } = await supabase
        .from('reputation_votes')
        .select('voted_id')
        .eq('voter_id', currentUserId)
        .eq('activity_id', activityId);
      return (data ?? []) as { voted_id: string }[];
    },
    enabled: !!activityId && !!currentUserId,
  });

  const ratedIds = new Set((existingVotes ?? []).map((v) => v.voted_id));
  const others = (participants ?? []).filter(
    (p) => p.status === 'accepted' && p.user_id !== currentUserId && !ratedIds.has(p.user_id),
  );

  // Auto-close when nothing left to rate
  useEffect(() => {
    if (isLoading || votesLoading) return;
    if ((participants ?? []).length > 0 && others.length === 0) {
      const timer = setTimeout(() => router.back(), 1200);
      return () => clearTimeout(timer);
    }
  }, [isLoading, votesLoading, participants, others.length, router]);

  // Pre-fill endorsements from existing votes
  useEffect(() => {
    if (!myEndorsements || myEndorsements.length === 0) return;
    const initial: Record<string, boolean> = {};
    for (const e of myEndorsements) initial[e.target_id] = e.is_confirmation;
    setEndorsements(initial);
  }, [myEndorsements]);

  const toggleBadge = (userId: string, badgeKey: string) => {
    setSelections((prev) => {
      const userSet = new Set(prev[userId] ?? []);
      if (userSet.has(badgeKey)) userSet.delete(badgeKey);
      else userSet.add(badgeKey);
      return { ...prev, [userId]: userSet };
    });
  };

  const setEndorsement = (userId: string, value: boolean | null) => {
    setEndorsements((prev) => {
      const next = { ...prev };
      if (value === null) delete next[userId];
      else next[userId] = value;
      return next;
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
      if (activity?.sport_key) {
        for (const [userId, isConfirmation] of Object.entries(endorsements)) {
          promises.push(endorsementService.submit(userId, activityId, activity.sport_key, isConfirmation));
        }
      }
      await Promise.all(promises);
      await queryClient.invalidateQueries({ queryKey: ['reputation'] });
      await queryClient.invalidateQueries({ queryKey: ['my-votes', activityId] });
      await queryClient.invalidateQueries({ queryKey: ['my-endorsements', activityId] });
      await queryClient.invalidateQueries({ queryKey: ['sport-endorsements'] });
      Burnt.toast({ title: t('rate.submitted'), preset: 'done' });
      router.back();
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'rateParticipants'));
    } finally {
      setIsSaving(false);
    }
  };

  const hasSelections =
    Object.values(selections).some((s) => s.size > 0)
    || Object.keys(endorsements).length > 0;

  if (isLoading || votesLoading) {
    return (
      <View style={styles.center}>
        <LogoSpinner size={48} />
      </View>
    );
  }

  if ((participants ?? []).length > 0 && others.length === 0) {
    return (
      <View style={styles.center}>
        <Text style={styles.title}>{t('rate.alreadyDone')}</Text>
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

            {activity?.sport_key && p.levels_per_sport?.[activity.sport_key] && (
              <>
                <Text style={styles.badgeGroupLabel}>
                  {t('rate.sportLevelTitle', {
                    sport: t(`sports.${activity.sport_key}`, { defaultValue: activity.sport_key }),
                    level: p.levels_per_sport[activity.sport_key],
                  })}
                </Text>
                <View style={styles.badgeRow}>
                  <Pressable
                    style={[styles.badgeChip, endorsements[p.user_id] === true && styles.badgeChipSelected]}
                    onPress={() => setEndorsement(p.user_id, endorsements[p.user_id] === true ? null : true)}
                  >
                    <Text style={[styles.badgeLabel, endorsements[p.user_id] === true && styles.badgeLabelSelected]}>
                      ✓ {t('rate.sportLevelConfirm')}
                    </Text>
                  </Pressable>
                  <Pressable
                    style={[styles.badgeChip, endorsements[p.user_id] === false && styles.badgeChipNegSelected]}
                    onPress={() => setEndorsement(p.user_id, endorsements[p.user_id] === false ? null : false)}
                  >
                    <Text style={[styles.badgeLabel, endorsements[p.user_id] === false && styles.badgeLabelNegSelected]}>
                      ✗ {t('rate.sportLevelContest')}
                    </Text>
                  </Pressable>
                </View>
              </>
            )}

            <Text style={styles.badgeGroupLabel}>{t('rate.positive')}</Text>
            <View style={styles.badgeRow}>
              {DISPLAYED_POSITIVE_BADGES.map((badge) => (
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

const createStyles = (colors: AppColors) => StyleSheet.create({
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
