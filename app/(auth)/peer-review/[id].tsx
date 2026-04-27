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

  const { data: state, isLoading, error: stateError } = useQuery({
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

  if (stateError) {
    return (
      <View style={styles.center}>
        <Text style={styles.empty}>RPC error</Text>
        <Text style={[styles.empty, { fontSize: 11, marginTop: 8, paddingHorizontal: 24, textAlign: 'center' }]}>
          {stateError instanceof Error ? stateError.message : String(stateError)}
        </Text>
      </View>
    );
  }
  if (!state || state.length === 0) {
    return (
      <View style={styles.center}>
        <Text style={styles.empty}>{t('peerReview.empty')}</Text>
        <Text style={[styles.empty, { fontSize: 11, marginTop: 8 }]}>
          (debug: id={id?.slice(0, 8)}…, rows={state?.length ?? 'undefined'})
        </Text>
      </View>
    );
  }

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <Text style={styles.title}>{activity.title}</Text>
      <Text style={styles.subtitle}>{t('peerReview.subtitle')}</Text>

      <View style={styles.grid}>
        {state.map((p) => {
          const presenceConfirmed = p.confirmed_present === true;
          return (
            <View key={p.user_id} style={styles.tile}>
              <UserAvatar name={p.display_name} avatarUrl={p.avatar_url} size={44} />
              <Text style={styles.name} numberOfLines={1}>{p.display_name}</Text>

              {/* Metro pill — all 9 badges separated by | */}
              <View style={styles.metroPill}>
                {[...POSITIVE_BADGES, ...NEGATIVE_BADGES].map((badge, i) => {
                  const voted = p.my_badge_votes.includes(badge.key);
                  const isPositive = i < POSITIVE_BADGES.length;
                  const showSep = i > 0;
                  return (
                    <View key={badge.key} style={styles.metroCellWrap}>
                      {showSep && <Text style={styles.metroSep}>|</Text>}
                      <Pressable
                        style={[
                          styles.metroCell,
                          voted && (isPositive ? styles.metroCellPositive : styles.metroCellNegative),
                        ]}
                        onPress={() => handleBadgeTap(p, badge.key)}
                        hitSlop={2}
                      >
                        <Text style={styles.metroIcon}>{badge.icon}</Text>
                      </Pressable>
                    </View>
                  );
                })}
              </View>

              {/* Presence pill — only when not yet confirmed */}
              {!presenceConfirmed && (
                <Pressable
                  style={[
                    styles.presencePill,
                    p.i_voted_presence && styles.presencePillVoted,
                  ]}
                  onPress={() => handlePresenceTap(p)}
                  disabled={p.i_voted_presence && !isCreator}
                >
                  <Text style={[styles.presenceText, p.i_voted_presence && styles.presenceTextVoted]}>
                    {p.i_voted_presence
                      ? t('peerReview.presenceVoted')
                      : t('peerReview.presenceVoteCta', { name: p.display_name })}
                  </Text>
                  {p.peer_validation_count > 0 && (
                    <Text style={styles.presenceCount}>{p.peer_validation_count}/2</Text>
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

const TILE_GAP = 12;

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.md, paddingBottom: spacing.xl + 16 },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.background },
  empty: { color: colors.textSecondary, fontSize: fontSizes.md },
  title: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800', marginBottom: 4 },
  subtitle: { color: colors.textSecondary, fontSize: fontSizes.sm, marginBottom: spacing.lg },

  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: TILE_GAP },
  tile: {
    width: '47%',
    flexGrow: 1,
    minWidth: 150,
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    padding: spacing.sm,
    gap: 6,
  },
  name: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700', maxWidth: '100%' },

  metroPill: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surfaceAlt,
    borderRadius: 999,
    paddingHorizontal: 6,
    paddingVertical: 4,
    gap: 0,
  },
  metroCellWrap: { flexDirection: 'row', alignItems: 'center' },
  metroSep: { color: colors.textSecondary, fontSize: 11, marginHorizontal: 1, opacity: 0.5 },
  metroCell: {
    paddingHorizontal: 3,
    paddingVertical: 2,
    borderRadius: 4,
  },
  metroCellPositive: { backgroundColor: colors.success + '40' },
  metroCellNegative: { backgroundColor: colors.error + '40' },
  metroIcon: { fontSize: 14 },

  presencePill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    backgroundColor: colors.cta + '1F',
    borderRadius: 999,
    paddingHorizontal: 10,
    paddingVertical: 6,
    marginTop: 2,
  },
  presencePillVoted: { backgroundColor: colors.success + '33' },
  presenceText: { color: colors.cta, fontSize: 11, fontWeight: '700', letterSpacing: 0.3 },
  presenceTextVoted: { color: colors.success },
  presenceCount: { color: colors.textSecondary, fontSize: 10, fontWeight: '600' },
});
