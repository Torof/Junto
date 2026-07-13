import { useMemo, useLayoutEffect, useState, useRef, useEffect } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet, Alert } from 'react-native';
import { useLocalSearchParams, useRouter, useNavigation } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import * as Burnt from 'burnt';
import dayjs from 'dayjs';
import {
  Clock, Backpack, Handshake, ShieldCheck,
  HelpCircle, Frown, Zap,
  ChevronDown, ChevronUp,
  type LucideIcon,
} from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { activityService } from '@/services/activity-service';
import { badgeService, POSITIVE_BADGES, NEGATIVE_BADGES, LEVEL_VOTE_KEYS, type PeerReviewParticipant } from '@/services/badge-service';
import { getSportIcon } from '@/constants/sport-icons';
import { UserAvatar } from '@/components/user-avatar';
import { getFriendlyError } from '@/utils/friendly-error';
import { supabase } from '@/services/supabase';
import { LogoSpinner } from '@/components/logo-spinner';
import { ActivityUnavailable } from '@/components/activity-unavailable';

// Per-trait Lucide icons — match the profile's vouched line for the
// positives, distinct shapes for the negatives that don't collide with
// the warning-severity icons (AlertTriangle / OctagonAlert) used on the
// profile body.
const POSITIVE_TRAIT_ICON: Record<string, LucideIcon> = {
  punctual: Clock,
  prepared: Backpack,
  conciliant: Handshake,
  prudent: ShieldCheck,
};
const NEGATIVE_TRAIT_ICON: Record<string, LucideIcon> = {
  unprepared: HelpCircle,
  aggressive: Frown,
  reckless: Zap,
};

// Peer review window — server gates anyway, this is the client-side
// urgency cue for the header. Activity end + 24h.
function parseDurationMs(d: string): number {
  if (d.includes(':')) {
    const [h, m, s] = d.split(':').map(Number);
    return ((h ?? 0) * 3600 + (m ?? 0) * 60 + (s ?? 0)) * 1000;
  }
  const match = d.match(/(\d+)\s*hour/);
  return match ? parseInt(match[1]!, 10) * 3600 * 1000 : 2 * 3600 * 1000;
}

export default function PeerReviewScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const queryClient = useQueryClient();

  // Force the lazy status transition to 'completed' on open. Otherwise an
  // activity that just ended is still 'in_progress' and peer_validate_presence
  // refuses ("not completed") with a vague error (Scott 2026-07-13).
  useEffect(() => {
    if (!id) return;
    supabase.rpc('transition_single_activity' as 'join_activity', {
      p_activity_id: id,
    } as unknown as { p_activity_id: string }).then((r) => {
      if (r.data) {
        queryClient.invalidateQueries({ queryKey: ['activity', id] });
        queryClient.invalidateQueries({ queryKey: ['peer-review-state', id] });
      }
    }, () => {});
  }, [id, queryClient]);
  const router = useRouter();
  const navigation = useNavigation();
  // Collapse state per participant. Default to expanded so unrated cards
  // are immediately actionable; user collapses by tapping the header
  // when they're done with a person.
  const [collapsed, setCollapsed] = useState<Record<string, boolean>>({});
  const toggleCollapse = (userId: string) =>
    setCollapsed((prev) => ({ ...prev, [userId]: !prev[userId] }));

  const { data: activity, isLoading: activityLoading } = useQuery({
    queryKey: ['activity', id],
    queryFn: () => activityService.getById(id ?? ''),
    enabled: !!id,
  });

  const { data: state, isLoading } = useQuery({
    queryKey: ['peer-review-state', id],
    queryFn: () => badgeService.getPeerReviewState(id ?? ''),
    enabled: !!id,
  });

  const refresh = () => {
    queryClient.invalidateQueries({ queryKey: ['peer-review-state', id] });
    queryClient.invalidateQueries({ queryKey: ['participants', id] });
    // The voted user's reliability_score may have changed (peer threshold flip)
    queryClient.invalidateQueries({ queryKey: ['user-public-stats'] });
    queryClient.invalidateQueries({ queryKey: ['public-profile'] });
  };

  // Per-(target, key) in-flight guard so a rapid double-tap before refresh()
  // lands can't fire give-then-give on the same vote.
  const votingRef = useRef<Set<string>>(new Set());

  const handleBadgeTap = async (target: PeerReviewParticipant, badgeKey: string) => {
    if (!canVote) {
      Alert.alert(t('auth.error'), windowState === 'closed' ? t('peerReview.errors.windowClosed') : t('peerReview.errors.windowNotOpen'));
      return;
    }
    const guardKey = `${target.user_id}:${badgeKey}`;
    if (votingRef.current.has(guardKey)) return;
    votingRef.current.add(guardKey);
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
      let userMsg = getFriendlyError(err, 'generic');
      if (msg.includes('badge_window_closed')) userMsg = t('peerReview.errors.windowClosed');
      else if (msg.includes('badge_window_not_open')) userMsg = t('peerReview.errors.windowNotOpen');
      else if (msg.includes('badge_rate_limit')) userMsg = t('errors.code.badge_rate_limit');
      else if (msg.includes('Operation not permitted')) userMsg = t('peerReview.notAllowed');
      Alert.alert(t('auth.error'), userMsg);
    } finally {
      votingRef.current.delete(guardKey);
    }
  };

  // Level votes are mutually exclusive on the server side: casting a new
  // level_* vote replaces any previous one from this voter for this target
  // on this activity. Tapping the same key revokes (toggle off).
  const handleLevelTap = async (target: PeerReviewParticipant, levelKey: string) => {
    if (!canVote) {
      Alert.alert(t('auth.error'), windowState === 'closed' ? t('peerReview.errors.windowClosed') : t('peerReview.errors.windowNotOpen'));
      return;
    }
    const guardKey = `${target.user_id}:${levelKey}`;
    if (votingRef.current.has(guardKey)) return;
    votingRef.current.add(guardKey);
    const alreadyVoted = target.my_badge_votes.includes(levelKey);
    try {
      if (alreadyVoted) {
        await badgeService.revokeReputationBadge(target.user_id, id ?? '', levelKey);
      } else {
        await badgeService.giveReputationBadge(target.user_id, id ?? '', levelKey);
      }
      refresh();
    } catch (err) {
      const msg = err instanceof Error ? err.message : '';
      let userMsg = getFriendlyError(err, 'generic');
      if (msg.includes('badge_window_closed')) userMsg = t('peerReview.errors.windowClosed');
      else if (msg.includes('badge_window_not_open')) userMsg = t('peerReview.errors.windowNotOpen');
      else if (msg.includes('badge_rate_limit')) userMsg = t('errors.code.badge_rate_limit');
      else if (msg.includes('Operation not permitted')) userMsg = t('peerReview.notAllowed');
      Alert.alert(t('auth.error'), userMsg);
    } finally {
      votingRef.current.delete(guardKey);
    }
  };

  const handlePresenceTap = async (target: PeerReviewParticipant) => {
    if (target.confirmed_present === true) return;
    if (!canVote) {
      Alert.alert(t('auth.error'), windowState === 'closed' ? t('peerReview.errors.windowClosed') : t('peerReview.errors.windowNotOpen'));
      return;
    }
    try {
      await badgeService.peerValidatePresence(target.user_id, id ?? '');
      Burnt.toast({ title: t('peerReview.presenceVoted'), preset: 'done' });
      refresh();
    } catch (err) {
      const msg = err instanceof Error ? err.message : '';
      let userMsg = t('peerReview.notAllowed');
      if (msg.includes('peer_review_no_presence')) userMsg = t('peerReview.errors.noPresence');
      else if (msg.includes('peer_review_target_not_in')) userMsg = t('peerReview.errors.targetNotIn');
      else if (msg.includes('peer_review_not_completed')) userMsg = t('peerReview.errors.notCompleted');
      else if (msg.includes('peer_review_window_not_open')) userMsg = t('peerReview.errors.windowNotOpen');
      else if (msg.includes('peer_review_window_closed')) userMsg = t('peerReview.errors.windowClosed');
      else if (msg.includes('peer_voter_not_present')) userMsg = t('peerReview.errors.voterNotPresent');
      else if (msg.includes('peer_already_validated')) userMsg = t('peerReview.errors.alreadyValidated');
      Alert.alert(t('auth.error'), userMsg);
    }
  };

  // Window expires at activity end + 24h. Computed before useLayoutEffect
  // so we can pass the urgency string to the navigation header.
  const endsAt = activity ? dayjs(activity.starts_at).add(parseDurationMs(activity.duration), 'millisecond') : null;
  const expiresAt = endsAt ? endsAt.add(24, 'hour') : null;
  // Vote window mirrors the server (give_reputation_badge / peer_validate):
  // opens 15 min after the end, closes 24 h after. Old notifications land here
  // after it closed — show a clear banner and skip the pointless RPC round-trip.
  const opensAt = endsAt ? endsAt.add(15, 'minute') : null;
  const nowRef = dayjs();
  const windowState: 'open' | 'notYetOpen' | 'closed' =
    !opensAt || !expiresAt ? 'open'
      : nowRef.isBefore(opensAt) ? 'notYetOpen'
      : nowRef.isAfter(expiresAt) ? 'closed'
      : 'open';
  const canVote = windowState === 'open';
  const hoursLeft = expiresAt ? Math.max(0, Math.round(expiresAt.diff(dayjs(), 'minute') / 60)) : 0;
  const urgencyLabel = hoursLeft > 0
    ? t('peerReview.windowLeft', { hours: hoursLeft, defaultValue: `${hoursLeft}h left` })
    : t('peerReview.windowClosed', { defaultValue: 'Window closed' });

  useLayoutEffect(() => {
    navigation.setOptions({
      headerTitle: () => (
        <View style={{ paddingLeft: spacing.md, gap: 1 }}>
          <Text style={{ color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800' }}>
            {t('peerReview.headerTitle', { defaultValue: 'Peer review' })}
          </Text>
          {activity && (
            <Text style={{ color: colors.textMuted, fontSize: 11.5, fontWeight: '600' }} numberOfLines={1}>
              {activity.title} · {urgencyLabel}
            </Text>
          )}
        </View>
      ),
      headerTitleAlign: 'left' as const,
    });
  }, [navigation, activity, urgencyLabel, colors, t]);

  // Activity still resolving → spinner. Resolved to nothing (deleted, expired,
  // or no longer accessible) → graceful unavailable instead of an endless
  // spinner. (Finished activities themselves now load via getById's fallback.)
  if (activityLoading) {
    return <View style={styles.center}><LogoSpinner /></View>;
  }
  if (!activity) {
    return <ActivityUnavailable fallbackHref="/(auth)/(tabs)/notifications" />;
  }
  if (isLoading) {
    return <View style={styles.center}><LogoSpinner /></View>;
  }

  if (!state || state.length === 0) {
    return <View style={styles.center}><Text style={styles.empty}>{t('peerReview.empty')}</Text></View>;
  }

  // Peer presence testimony needs 3+ (state excludes self → length >= 2) AND
  // the activity to actually require presence — otherwise there's nothing to
  // validate and peer_validate_presence rejects it (Scott 2026-07-13, a
  // requires_presence=false activity was still showing the button).
  const peerPresenceEnabled = state.length >= 2 && activity.requires_presence === true;

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <Text style={styles.subtitle}>{t('peerReview.subtitle')}</Text>

      {windowState !== 'open' && (
        <View style={[styles.banner, windowState === 'closed' ? styles.bannerClosed : styles.bannerInfo]}>
          <Text style={styles.bannerText}>
            {windowState === 'closed'
              ? t('peerReview.bannerClosed', { defaultValue: "La fenêtre d'évaluation est fermée (24 h après la fin). Tu ne peux plus voter." })
              : t('peerReview.bannerNotOpen', { defaultValue: "L'évaluation ouvrira 15 min après la fin de la sortie." })}
          </Text>
        </View>
      )}

      <View style={styles.list}>
        {state.map((p) => {
          const presenceConfirmed = p.confirmed_present === true;
          const isCollapsed = collapsed[p.user_id] === true;
          // Quick "completion" cue while collapsed: how many trait votes
          // the user has cast for this person (presence + traits + level).
          const voteCount = p.my_badge_votes.length + (p.i_voted_presence ? 1 : 0);
          return (
            <View key={p.user_id} style={styles.card}>
              <Pressable
                onPress={() => toggleCollapse(p.user_id)}
                style={({ pressed }) => [styles.cardHeader, pressed && styles.tappedDim]}
                hitSlop={6}
              >
                <UserAvatar
                  name={p.display_name}
                  avatarUrl={p.avatar_url}
                  size={44}
                  confirmedPresent={presenceConfirmed}
                />
                <Text style={styles.cardName} numberOfLines={1}>{p.display_name}</Text>
                {voteCount > 0 && isCollapsed && (
                  <Text style={styles.cardVoteCount}>·{voteCount}</Text>
                )}
                {isCollapsed
                  ? <ChevronDown size={18} color={colors.textMuted} strokeWidth={2.2} />
                  : <ChevronUp size={18} color={colors.textMuted} strokeWidth={2.2} />}
              </Pressable>

              {!isCollapsed && (
                <>
              {/* Presence above the trait pills — it's the gate, not a nuance.
                  Hidden below 3 participants (state excludes self, so length < 2):
                  peer presence testimony is circular at 2 — QR/geo only there,
                  and the server (peer_validate_presence) rejects it anyway. */}
              {!presenceConfirmed && peerPresenceEnabled && (
                <Pressable
                  style={({ pressed }) => [
                    styles.presencePill,
                    p.i_voted_presence && styles.presencePillVoted,
                    pressed && !p.i_voted_presence && styles.tappedDim,
                  ]}
                  onPress={() => handlePresenceTap(p)}
                  disabled={p.i_voted_presence}
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

              {/* Positives — own row so cell widths are uniform. */}
              <Text style={styles.sectionLabel}>{t('peerReview.sectionPositives')}</Text>
              <View style={styles.metroPill}>
                {POSITIVE_BADGES.map((badge) => {
                  const voted = p.my_badge_votes.includes(badge.key);
                  const Icon = POSITIVE_TRAIT_ICON[badge.key];
                  return (
                    <Pressable
                      key={badge.key}
                      style={({ pressed }) => [
                        styles.metroCell,
                        voted && styles.metroCellPositive,
                        pressed && styles.tappedDim,
                      ]}
                      onPress={() => handleBadgeTap(p, badge.key)}
                    >
                      {Icon && (
                        <Icon
                          size={16}
                          color={voted ? colors.success : colors.textSecondary}
                          strokeWidth={2.2}
                        />
                      )}
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
              </View>

              {/* Negatives — separate row, equal cell widths within. */}
              <Text style={styles.sectionLabel}>{t('peerReview.sectionNegatives')}</Text>
              <View style={styles.metroPill}>
                {NEGATIVE_BADGES.map((badge) => {
                  const voted = p.my_badge_votes.includes(badge.key);
                  const Icon = NEGATIVE_TRAIT_ICON[badge.key];
                  return (
                    <Pressable
                      key={badge.key}
                      style={({ pressed }) => [
                        styles.metroCell,
                        voted && styles.metroCellNegative,
                        pressed && styles.tappedDim,
                      ]}
                      onPress={() => handleBadgeTap(p, badge.key)}
                    >
                      {Icon && (
                        <Icon
                          size={16}
                          color={voted ? colors.error : colors.textSecondary}
                          strokeWidth={2.2}
                        />
                      )}
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

              {activity.sport_key && p.declared_level && (
                <Text style={styles.sectionLabel}>{t('peerReview.sectionLevel')}</Text>
              )}
              {activity.sport_key && p.declared_level && (
                <Text style={styles.selfLevelLine}>
                  {t('peerReview.selfLevel', {
                    name: p.display_name,
                    level: p.declared_level,
                    defaultValue: '{{name}} se dit de niveau {{level}}',
                  })}
                </Text>
              )}
              {activity.sport_key && p.declared_level && (
                <View style={styles.levelPill}>
                  <Text style={styles.levelSportIcon}>{getSportIcon(activity.sport_key)}</Text>
                  <View style={styles.levelDivider} />
                  {LEVEL_VOTE_KEYS.map((levelKey) => {
                    const voted = p.my_badge_votes.includes(levelKey);
                    return (
                      <Pressable
                        key={levelKey}
                        style={({ pressed }) => [
                          styles.levelCell,
                          voted && styles.levelCellActive,
                          pressed && styles.tappedDim,
                        ]}
                        onPress={() => handleLevelTap(p, levelKey)}
                      >
                        <Text
                          style={[styles.levelLabel, voted && styles.levelLabelActive]}
                          numberOfLines={1}
                          adjustsFontSizeToFit
                          minimumFontScale={0.7}
                        >
                          {t(`badges.short.${levelKey}`)}
                        </Text>
                      </Pressable>
                    );
                  })}
                </View>
              )}
                </>
              )}
            </View>
          );
        })}
      </View>

      <Pressable
        style={({ pressed }) => [styles.submitButton, pressed && styles.tappedDim]}
        onPress={() => router.back()}
      >
        <Text style={styles.submitText}>{t('peerReview.close', { defaultValue: 'Fermer' })}</Text>
      </Pressable>
    </ScrollView>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.md, paddingBottom: spacing.xl + 16 },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.background },
  empty: { color: colors.textSecondary, fontSize: fontSizes.md },
  subtitle: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
    marginBottom: spacing.lg,
  },
  tappedDim: { opacity: 0.55 },
  banner: {
    borderRadius: radius.md,
    padding: spacing.md,
    marginBottom: spacing.lg,
    borderWidth: 1,
  },
  bannerClosed: { backgroundColor: colors.error + '14', borderColor: colors.error + '40' },
  bannerInfo: { backgroundColor: colors.warning + '14', borderColor: colors.warning + '40' },
  bannerText: { color: colors.textPrimary, fontSize: fontSizes.sm, lineHeight: 20, fontWeight: '600' },
  sectionLabel: {
    color: colors.textMuted,
    fontSize: 10.5,
    fontWeight: '700',
    letterSpacing: 1.4,
    textTransform: 'uppercase',
    marginTop: spacing.sm,
    marginBottom: 4,
  },
  selfLevelLine: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
    marginBottom: 6,
  },

  list: { gap: spacing.md },
  card: {
    backgroundColor: 'transparent',
    borderRadius: radius.sm,
    borderWidth: 1,
    borderColor: colors.borderMuted,
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
  cardVoteCount: {
    color: colors.textMuted,
    fontSize: 12,
    fontWeight: '700',
    letterSpacing: -0.01,
  },

  metroPill: {
    flexDirection: 'row',
    backgroundColor: 'transparent',
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.sm,
    overflow: 'hidden',
    marginTop: spacing.xs,
  },
  metroCell: {
    flex: 1,
    paddingVertical: 8,
    paddingHorizontal: 2,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 3,
  },
  metroCellPositive: { backgroundColor: colors.success + '26' },
  metroCellNegative: { backgroundColor: colors.error + '26' },
  metroLabel: {
    color: colors.textSecondary,
    fontSize: 10.5,
    fontWeight: '700',
    textAlign: 'center',
  },
  metroLabelVotedPositive: { color: colors.success, fontWeight: '800' },
  metroLabelVotedNegative: { color: colors.error, fontWeight: '800' },

  levelPill: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'transparent',
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.sm,
    overflow: 'hidden',
    marginTop: spacing.xs,
  },
  levelSportIcon: {
    fontSize: 18,
    lineHeight: 20,
    paddingHorizontal: 10,
  },
  levelDivider: {
    width: 1,
    backgroundColor: colors.borderMuted,
    marginVertical: 6,
  },
  levelCell: {
    flex: 1,
    paddingVertical: 8,
    paddingHorizontal: 4,
    alignItems: 'center',
    justifyContent: 'center',
  },
  levelCellActive: {
    backgroundColor: colors.cta + '26',
  },
  levelLabel: {
    color: colors.textSecondary,
    fontSize: 11,
    fontWeight: '700',
    textAlign: 'center',
  },
  levelLabelActive: {
    color: colors.cta,
    fontWeight: '800',
  },

  presencePill: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    backgroundColor: 'transparent',
    borderWidth: 1,
    borderColor: colors.cta,
    borderRadius: radius.sm,
    paddingHorizontal: spacing.md,
    paddingVertical: 8,
    marginTop: spacing.xs,
  },
  presencePillVoted: { backgroundColor: colors.success + '33', borderColor: colors.success },
  presenceText: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700' },
  presenceTextVoted: { color: colors.success },
  presenceCount: { color: colors.textSecondary, fontSize: 11, fontWeight: '700' },

  submitButton: {
    alignSelf: 'center',
    marginTop: spacing.lg,
    backgroundColor: colors.cta,
    borderRadius: radius.sm,
    paddingVertical: 10,
    paddingHorizontal: 28,
  },
  submitText: {
    color: '#FFFFFF',
    fontSize: fontSizes.sm,
    fontWeight: '700',
  },
});
