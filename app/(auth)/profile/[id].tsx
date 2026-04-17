import { View, Text, Pressable, ScrollView, StyleSheet, Alert, Modal, ActivityIndicator } from 'react-native';
import { useLocalSearchParams, useNavigation, useRouter } from 'expo-router';
import { MoreHorizontal } from 'lucide-react-native';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import * as Burnt from 'burnt';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { userService } from '@/services/user-service';
import { badgeService } from '@/services/badge-service';
import { conversationService } from '@/services/conversation-service';
import { useLayoutEffect, useState } from 'react';
import { UserAvatar } from '@/components/user-avatar';
import { ReliabilityRing } from '@/components/reliability-ring';
import { BadgeDisplay } from '@/components/badge-display';
import { SportIconGrid } from '@/components/sport-icon-grid';
import { ReportModal } from '@/components/report-modal';
import { supabase } from '@/services/supabase';

export default function PublicProfileScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { t, i18n } = useTranslation();
  const router = useRouter();
  const navigation = useNavigation();
  const [showReport, setShowReport] = useState(false);
  const [showMenu, setShowMenu] = useState(false);
  const queryClient = useQueryClient();

  const { data: currentUser } = useQuery({
    queryKey: ['currentUser-id'],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id,
  });

  const isOwnProfile = currentUser === id;

  const { data: profile, isLoading } = useQuery({
    queryKey: ['public-profile', id],
    queryFn: () => userService.getPublicProfile(id ?? ''),
    enabled: !!id,
  });

  const { data: stats } = useQuery({
    queryKey: ['user-stats', id],
    queryFn: () => userService.getPublicStats(id ?? ''),
    enabled: !!id,
  });

  const { data: sportBreakdown } = useQuery({
    queryKey: ['user-sport-breakdown', id],
    queryFn: () => userService.getSportBreakdown(id ?? ''),
    enabled: !!id,
  });

  const { data: isBlocked } = useQuery({
    queryKey: ['is-blocked', id],
    queryFn: () => userService.isBlocked(id ?? ''),
    enabled: !!id && !isOwnProfile,
  });

  const { data: reputation } = useQuery({
    queryKey: ['reputation', id],
    queryFn: () => badgeService.getUserReputation(id ?? ''),
    enabled: !!id,
  });

  const { data: trophies } = useQuery({
    queryKey: ['trophies', id],
    queryFn: () => badgeService.getUserTrophies(id ?? ''),
    enabled: !!id,
  });

  useLayoutEffect(() => {
    navigation.setOptions({
      headerTitle: () => (
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, paddingLeft: spacing.md }}>
          <Text style={{ color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold' }}>
            {profile?.display_name ?? '...'}
          </Text>
        </View>
      ),
      headerTitleAlign: 'left' as const,
      headerRight: () =>
        isOwnProfile ? null : (
          <Pressable onPress={() => setShowMenu(true)} hitSlop={12} style={{ paddingHorizontal: spacing.md }}>
            <MoreHorizontal size={24} color={colors.textPrimary} strokeWidth={2.2} />
          </Pressable>
        ),
    });
  }, [navigation, isOwnProfile, profile?.display_name]);

  const handleBlock = () => {
    Alert.alert(t('publicProfile.blockConfirmTitle'), t('publicProfile.blockConfirmMessage'), [
      { text: t('activity.no'), style: 'cancel' },
      {
        text: t('activity.yes'),
        style: 'destructive',
        onPress: async () => {
          await userService.blockUser(id ?? '');
          await queryClient.invalidateQueries({ queryKey: ['is-blocked', id] });
          Burnt.toast({ title: t('publicProfile.blocked') });
        },
      },
    ]);
  };

  const handleUnblock = async () => {
    await userService.unblockUser(id ?? '');
    await queryClient.invalidateQueries({ queryKey: ['is-blocked', id] });
    Burnt.toast({ title: t('publicProfile.unblocked') });
  };

  if (isLoading || !profile) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color={colors.cta} />
      </View>
    );
  }

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      {/* Hero row: avatar with ring + stats */}
      <View style={styles.heroRow}>
        <ReliabilityRing score={stats?.reliability_score ?? null} size={110}>
          <UserAvatar name={profile.display_name} avatarUrl={profile.avatar_url} size={110} />
        </ReliabilityRing>

        <View style={styles.statsColumn}>
          <Text style={styles.statsCardTitle}>{t('profil.activities')}</Text>
          <View style={styles.statsCard}>
            <View style={styles.statsRow}>
              <View style={styles.stat}>
                <Text style={styles.statNumber}>{stats?.completed_activities ?? 0}</Text>
                <Text style={styles.statLabel}>{t('profil.completed')}</Text>
              </View>
              <View style={styles.statDivider} />
              <View style={styles.stat}>
                <Text style={styles.statNumber}>{stats?.created_activities ?? 0}</Text>
                <Text style={styles.statLabel}>{t('profil.created')}</Text>
              </View>
              <View style={styles.statDivider} />
              <View style={styles.stat}>
                <Text style={styles.statNumber}>{stats?.joined_activities ?? 0}</Text>
                <Text style={styles.statLabel}>{t('profil.joined')}</Text>
              </View>
            </View>
          </View>
          {profile.created_at && (
            <Text style={styles.memberSince}>
              {t('profil.memberSince', { date: dayjs(profile.created_at).locale(i18n.language).format('MMM YYYY') })}
            </Text>
          )}
        </View>
      </View>

      {/* Sports icon grid */}
      <SportIconGrid rows={sportBreakdown ?? []} />

      {/* Badges */}
      <View style={styles.badgesSection}>
        <Text style={[styles.sectionTitle, { marginBottom: spacing.md }]}>{t('profil.badgesSection')}</Text>
        <BadgeDisplay reputation={reputation ?? []} trophies={trophies ?? []} />
      </View>

      {/* Primary action — send message (on other people's profile) */}
      {!isOwnProfile && (
        <View style={styles.actions}>
          <Pressable style={styles.messageButton} onPress={async () => {
            try {
              const conversationId = await conversationService.createOrGet(id ?? '');
              router.push(`/(auth)/conversation/${conversationId}`);
            } catch {
              Alert.alert(t('auth.error'), t('auth.unknownError'));
            }
          }}>
            <Text style={styles.messageText}>{t('publicProfile.sendMessage')}</Text>
          </Pressable>
        </View>
      )}

      {/* Overflow menu: block / report */}
      <Modal visible={showMenu} animationType="fade" transparent>
        <Pressable style={styles.menuBackdrop} onPress={() => setShowMenu(false)}>
          <Pressable style={styles.menuSheet} onPress={() => {}}>
            {isBlocked ? (
              <Pressable style={styles.menuItem} onPress={() => { setShowMenu(false); void handleUnblock(); }}>
                <Text style={styles.menuItemText}>{t('publicProfile.unblock')}</Text>
              </Pressable>
            ) : (
              <Pressable style={styles.menuItem} onPress={() => { setShowMenu(false); handleBlock(); }}>
                <Text style={[styles.menuItemText, { color: colors.error }]}>{t('publicProfile.block')}</Text>
              </Pressable>
            )}
            <View style={styles.menuDivider} />
            <Pressable style={styles.menuItem} onPress={() => { setShowMenu(false); setShowReport(true); }}>
              <Text style={[styles.menuItemText, { color: colors.error }]}>{t('report.reportUser')}</Text>
            </Pressable>
          </Pressable>
        </Pressable>
      </Modal>

      <ReportModal
        visible={showReport}
        targetType="user"
        targetId={id ?? ''}
        onClose={() => setShowReport(false)}
      />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.lg, paddingBottom: spacing.xl + 32 },
  center: { flex: 1, backgroundColor: colors.background, alignItems: 'center', justifyContent: 'center' },
  heroRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.lg,
    marginBottom: spacing.xl,
  },
  statsColumn: {
    flex: 1,
    justifyContent: 'center',
    gap: spacing.sm,
  },
  statsCardTitle: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: 'bold',
    letterSpacing: 0.8,
    textTransform: 'uppercase',
    textAlign: 'center',
    marginBottom: spacing.xs,
  },
  statsCard: {
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.xs,
  },
  statsRow: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    alignItems: 'center',
  },
  stat: { alignItems: 'center', flex: 1 },
  statDivider: { width: 1, height: 28, backgroundColor: colors.textSecondary, opacity: 0.2 },
  statNumber: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold' },
  statLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: 2, textAlign: 'center' },
  memberSince: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs - 1,
    textAlign: 'center',
    marginTop: spacing.xs,
    opacity: 0.7,
  },
  sectionTitle: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: 'bold',
    letterSpacing: 0.8,
    textTransform: 'uppercase',
  },
  badgesSection: { marginBottom: spacing.lg, marginTop: -spacing.xs },
  actions: { marginTop: spacing.lg, gap: spacing.sm },
  messageButton: {
    backgroundColor: colors.cta, borderRadius: radius.full,
    paddingVertical: spacing.md, alignItems: 'center',
  },
  messageText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: 'bold' },
  menuBackdrop: { flex: 1, alignItems: 'flex-end', paddingTop: 56, paddingRight: spacing.md },
  menuSheet: {
    backgroundColor: colors.surface, borderRadius: radius.lg,
    minWidth: 220, paddingVertical: spacing.xs,
    elevation: 6, shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.3, shadowRadius: 4,
  },
  menuItem: { paddingHorizontal: spacing.md, paddingVertical: spacing.sm },
  menuItemText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '500' },
  menuDivider: { height: 1, backgroundColor: colors.background, marginVertical: 2 },
});
