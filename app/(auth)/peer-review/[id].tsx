import { useMemo } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet, Alert } from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import * as Burnt from 'burnt';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { activityService } from '@/services/activity-service';
import { badgeService, POSITIVE_BADGES, NEGATIVE_BADGES, type PeerReviewParticipant } from '@/services/badge-service';
import { supabase } from '@/services/supabase';
import { UserAvatar } from '@/components/user-avatar';
import { LogoSpinner } from '@/components/logo-spinner';

export default function PeerReviewScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const queryClient = useQueryClient();

  const { data: currentUserId } = useQuery({
    queryKey: ['currentUser-id'],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id,
  });

  const { data: activity } = useQuery({
    queryKey: ['activity', id],
    queryFn: () => activityService.getById(id ?? ''),
    enabled: !!id,
  });

  const { data: state, isLoading } = useQuery({
    queryKey: ['peer-review-state', id],
    queryFn: () => badgeService.getPeerReviewState(id ?? ''),
    enabled: !!id,
  });

  const isCreator = activity?.creator_id === currentUserId;

  const refresh = () => {
    queryClient.invalidateQueries({ queryKey: ['peer-review-state', id] });
    queryClient.invalidateQueries({ queryKey: ['participants', id] });
    // The voted user's reliability_score may have changed (peer threshold flip)
    queryClient.invalidateQueries({ queryKey: ['user-public-stats'] });
    queryClient.invalidateQueries({ queryKey: ['public-profile'] });
  };

  const handleBadgeTap = async (target: PeerReviewParticipant, badgeKey: string) => {
    const alreadyVoted = target.my_badge_votes.includes(badgeKey);
    try {
      if (alreadyVoted) {
        await badgeService.revokeReputationBadge(target.user_id, id ?? '', badgeKey);
      } else {
        await badgeService.giveReputationBadge(target.user_id, id ?? '', badgeKey);
      }
      refresh();
    } catch (err) {
      const msg = err instanceof Error ? err.message : '';
      Alert.alert(t('auth.error'), msg.includes('Operation not permitted') ? t('peerReview.notAllowed') : msg);
    }
  };

  const handlePresenceTap = async (target: PeerReviewParticipant) => {
    if (target.confirmed_present === true) return;
    try {
      // peer_validate_presence routes itself: creator path = direct flip, peer path = 2-vote threshold
      await badgeService.peerValidatePresence(target.user_id, id ?? '');
      Burnt.toast({
        title: isCreator ? t('peerReview.presenceFlipped') : t('peerReview.presenceVoted'),
        preset: 'done',
      });
      refresh();
    } catch (err) {
      const msg = err instanceof Error ? err.message : '';
      Alert.alert(t('auth.error'), msg.includes('Operation not permitted') ? t('peerReview.notAllowed') : msg);
    }
  };

  if (isLoading || !activity) {
    return <View style={styles.center}><LogoSpinner /></View>;
  }

  if (!state || state.length === 0) {
    return <View style={styles.center}><Text style={styles.empty}>{t('peerReview.empty')}</Text></View>;
  }

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <Text style={styles.title}>{activity.title}</Text>
      <Text style={styles.subtitle}>{t('peerReview.subtitle')}</Text>

      <View style={styles.list}>
        {state.map((p) => {
          const presenceConfirmed = p.confirmed_present === true;
          return (
            <View key={p.user_id} style={styles.card}>
              {/* Header: avatar + name + presence dot */}
              <View style={styles.cardHeader}>
                <UserAvatar
                  name={p.display_name}
                  avatarUrl={p.avatar_url}
                  size={44}
                  confirmedPresent={presenceConfirmed}
                />
                <Text style={styles.cardName} numberOfLines={1}>{p.display_name}</Text>
              </View>

              {/* Qualities */}
              <Text style={styles.sectionLabel}>{t('peerReview.qualities')}</Text>
              <View style={styles.badgeGrid}>
                {POSITIVE_BADGES.map((badge) => {
                  const voted = p.my_badge_votes.includes(badge.key);
                  return (
                    <Pressable
                      key={badge.key}
                      style={[styles.badgePill, voted && styles.badgePillPositiveVoted]}
                      onPress={() => handleBadgeTap(p, badge.key)}
                    >
                      <Text style={styles.badgePillEmoji}>{badge.icon}</Text>
                      <Text style={[styles.badgePillLabel, voted && styles.badgePillLabelVoted]} numberOfLines={1}>
                        {t(`badges.${badge.key}`)}
                      </Text>
                    </Pressable>
                  );
                })}
              </View>

              {/* Concerns */}
              <Text style={[styles.sectionLabel, styles.sectionLabelMuted]}>{t('peerReview.concerns')}</Text>
              <View style={styles.badgeGrid}>
                {NEGATIVE_BADGES.map((badge) => {
                  const voted = p.my_badge_votes.includes(badge.key);
                  return (
                    <Pressable
                      key={badge.key}
                      style={[styles.badgePill, styles.badgePillNegative, voted && styles.badgePillNegativeVoted]}
                      onPress={() => handleBadgeTap(p, badge.key)}
                    >
                      <Text style={styles.badgePillEmoji}>{badge.icon}</Text>
                      <Text style={[styles.badgePillLabel, voted && styles.badgePillLabelVoted]} numberOfLines={1}>
                        {t(`badges.${badge.key}`)}
                      </Text>
                    </Pressable>
                  );
                })}
              </View>

              {/* Presence vote — only when not yet confirmed */}
              {!presenceConfirmed && (
                <Pressable
                  style={[styles.presencePill, p.i_voted_presence && styles.presencePillVoted]}
                  onPress={() => handlePresenceTap(p)}
                  disabled={p.i_voted_presence && !isCreator}
                >
                  <Text style={[styles.presenceText, p.i_voted_presence && styles.presenceTextVoted]}>
                    {p.i_voted_presence
                      ? t('peerReview.presenceVoted')
                      : t('peerReview.presenceVoteCta', { name: p.display_name })}
                  </Text>
                  {p.peer_validation_count > 0 && (
                    <Text style={styles.presenceCount}>×{p.peer_validation_count}</Text>
                  )}
                </Pressable>
              )}
            </View>
          );
        })}
      </View>
    </ScrollView>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.md, paddingBottom: spacing.xl + 16 },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.background },
  empty: { color: colors.textSecondary, fontSize: fontSizes.md },
  title: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800', marginBottom: 4 },
  subtitle: { color: colors.textSecondary, fontSize: fontSizes.sm, marginBottom: spacing.lg },

  list: { gap: spacing.md },
  card: {
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.line,
    padding: spacing.md,
    gap: spacing.sm,
  },
  cardHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    marginBottom: spacing.xs,
  },
  cardName: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    fontWeight: '800',
    flex: 1,
  },

  sectionLabel: {
    color: colors.textSecondary,
    fontSize: 10,
    fontWeight: '700',
    letterSpacing: 1.2,
    textTransform: 'uppercase',
    marginTop: 4,
    marginBottom: 2,
  },
  sectionLabelMuted: {
    opacity: 0.7,
  },

  badgeGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 6,
  },
  badgePill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    backgroundColor: colors.surfaceAlt,
    borderRadius: 999,
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderWidth: 1,
    borderColor: 'transparent',
  },
  badgePillNegative: {
    opacity: 0.85,
  },
  badgePillPositiveVoted: {
    backgroundColor: colors.success + '22',
    borderColor: colors.success + '66',
  },
  badgePillNegativeVoted: {
    backgroundColor: colors.error + '22',
    borderColor: colors.error + '66',
    opacity: 1,
  },
  badgePillEmoji: { fontSize: 14 },
  badgePillLabel: {
    color: colors.textPrimary,
    fontSize: 12,
    fontWeight: '600',
  },
  badgePillLabelVoted: {
    fontWeight: '800',
  },

  presencePill: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    backgroundColor: colors.cta + '1F',
    borderRadius: 999,
    paddingHorizontal: spacing.md,
    paddingVertical: 8,
    marginTop: spacing.xs,
  },
  presencePillVoted: { backgroundColor: colors.success + '33' },
  presenceText: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700' },
  presenceTextVoted: { color: colors.success },
  presenceCount: { color: colors.textSecondary, fontSize: 11, fontWeight: '700' },
});
