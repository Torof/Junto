import { useMemo } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet, Alert } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import * as Burnt from 'burnt';
import dayjs from 'dayjs';
import {
  Clock, Backpack, Handshake, ShieldCheck,
  HelpCircle, Frown, Zap,
  type LucideIcon,
} from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { activityService } from '@/services/activity-service';
import { badgeService, POSITIVE_BADGES, NEGATIVE_BADGES, LEVEL_VOTE_KEYS, type PeerReviewParticipant } from '@/services/badge-service';
import { getSportIcon } from '@/constants/sport-icons';
import { UserAvatar } from '@/components/user-avatar';
import { LogoSpinner } from '@/components/logo-spinner';

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
  const router = useRouter();

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

  // Level votes are mutually exclusive on the server side: casting a new
  // level_* vote replaces any previous one from this voter for this target
  // on this activity. Tapping the same key revokes (toggle off).
  const handleLevelTap = async (target: PeerReviewParticipant, levelKey: string) => {
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
      Alert.alert(t('auth.error'), msg.includes('Operation not permitted') ? t('peerReview.notAllowed') : msg);
    }
  };

  const handlePresenceTap = async (target: PeerReviewParticipant) => {
    if (target.confirmed_present === true) return;
    try {
      await badgeService.peerValidatePresence(target.user_id, id ?? '');
      Burnt.toast({ title: t('peerReview.presenceVoted'), preset: 'done' });
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

  // Window expires at end + 24h. Show a discreet "X h restantes" cue so
  // users know to act. Server still gates the writes either way.
  const endsAt = dayjs(activity.starts_at).add(parseDurationMs(activity.duration), 'millisecond');
  const expiresAt = endsAt.add(24, 'hour');
  const hoursLeft = Math.max(0, Math.round(expiresAt.diff(dayjs(), 'minute') / 60));
  const urgencyLabel = hoursLeft > 0
    ? t('peerReview.windowLeft', { hours: hoursLeft, defaultValue: `${hoursLeft}h left` })
    : t('peerReview.windowClosed', { defaultValue: 'Window closed' });

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <Text style={styles.title}>{activity.title}</Text>
      <View style={styles.subtitleRow}>
        <Text style={styles.subtitle}>{t('peerReview.subtitle')}</Text>
        <Text style={styles.urgency}>{urgencyLabel}</Text>
      </View>

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

              {/* Presence above the trait pills — it's the gate, not a nuance. */}
              {!presenceConfirmed && (
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

              {activity.sport_key && (
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
  title: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800', marginBottom: 4 },
  subtitleRow: {
    flexDirection: 'row',
    alignItems: 'baseline',
    justifyContent: 'space-between',
    gap: spacing.sm,
    marginBottom: spacing.lg,
  },
  subtitle: { color: colors.textSecondary, fontSize: fontSizes.sm, flexShrink: 1 },
  urgency: {
    color: colors.textMuted,
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 0.4,
    textTransform: 'uppercase',
  },
  tappedDim: { opacity: 0.55 },

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
    backgroundColor: colors.surfaceAlt,
    borderRadius: 12,
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
    backgroundColor: colors.line,
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
