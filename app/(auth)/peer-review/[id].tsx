import { useMemo } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet, Alert } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
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
  const router = useRouter();

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
      // peer_validate_presence routes itself: creator path = direct flip, peer path = threshold
      await badgeService.peerValidatePresence(target.user_id, id ?? '');
      Burnt.toast({
        title: isCreator ? t('peerReview.presenceFlipped') : t('peerReview.presenceVoted'),
        preset: 'done',
      });
      refresh();
    } catch (err) {
      const msg = err instanceof Error ? err.message : '';
      let userMsg = t('peerReview.notAllowed');
      if (msg.includes('peer_review_window_not_open')) userMsg = t('peerReview.errors.windowNotOpen');
      else if (msg.includes('peer_review_window_closed')) userMsg = t('peerReview.errors.windowClosed');
      else if (msg.includes('peer_voter_not_present')) userMsg = t('peerReview.errors.voterNotPresent');
      else if (msg.includes('peer_already_validated')) userMsg = t('peerReview.errors.alreadyValidated');
      Alert.alert(t('auth.error'), userMsg);
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
              <View style={styles.cardHeader}>
                <UserAvatar
                  name={p.display_name}
                  avatarUrl={p.avatar_url}
                  size={44}
                  confirmedPresent={presenceConfirmed}
                />
                <Text style={styles.cardName} numberOfLines={1}>{p.display_name}</Text>
              </View>

              <View style={styles.metroPill}>
                {POSITIVE_BADGES.map((badge) => {
                  const voted = p.my_badge_votes.includes(badge.key);
                  return (
                    <Pressable
                      key={badge.key}
                      style={[styles.metroCell, voted && styles.metroCellPositive]}
                      onPress={() => handleBadgeTap(p, badge.key)}
                    >
                      <Text style={styles.metroEmoji}>{badge.icon}</Text>
                      <Text
                        style={[styles.metroLabel, voted && styles.metroLabelVotedPositive]}
                        numberOfLines={1}
                        adjustsFontSizeToFit
                        minimumFontScale={0.7}
                      >
                        {t(`badges.short.${badge.key}`)}
                      </Text>
                    </Pressable>
                  );
                })}
                <View style={styles.metroDivider} />
                {NEGATIVE_BADGES.map((badge) => {
                  const voted = p.my_badge_votes.includes(badge.key);
                  return (
                    <Pressable
                      key={badge.key}
                      style={[styles.metroCell, voted && styles.metroCellNegative]}
                      onPress={() => handleBadgeTap(p, badge.key)}
                    >
                      <Text style={styles.metroEmoji}>{badge.icon}</Text>
                      <Text
                        style={[styles.metroLabel, voted && styles.metroLabelVotedNegative]}
                        numberOfLines={1}
                        adjustsFontSizeToFit
                        minimumFontScale={0.7}
                      >
                        {t(`badges.short.${badge.key}`)}
                      </Text>
                    </Pressable>
                  );
                })}
              </View>

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

      <Pressable style={styles.submitButton} onPress={() => router.back()}>
        <Text style={styles.submitText}>{t('peerReview.submit')}</Text>
      </Pressable>
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

  metroPill: {
    flexDirection: 'row',
    backgroundColor: colors.surfaceAlt,
    borderRadius: 12,
    overflow: 'hidden',
    marginTop: spacing.xs,
  },
  metroCell: {
    flex: 1,
    paddingVertical: 8,
    paddingHorizontal: 2,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 2,
  },
  metroDivider: {
    width: 1,
    backgroundColor: colors.line,
    marginVertical: 6,
  },
  metroCellPositive: { backgroundColor: colors.success + '26' },
  metroCellNegative: { backgroundColor: colors.error + '26' },
  metroEmoji: { fontSize: 18, lineHeight: 20 },
  metroLabel: {
    color: colors.textSecondary,
    fontSize: 10,
    fontWeight: '700',
    textAlign: 'center',
  },
  metroLabelVotedPositive: { color: colors.success, fontWeight: '800' },
  metroLabelVotedNegative: { color: colors.error, fontWeight: '800' },

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

  submitButton: {
    alignSelf: 'center',
    marginTop: spacing.lg,
    backgroundColor: colors.cta + '1F',
    borderRadius: 999,
    paddingVertical: 10,
    paddingHorizontal: 28,
  },
  submitText: {
    color: colors.cta,
    fontSize: fontSizes.sm,
    fontWeight: '700',
  },
});
