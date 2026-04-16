import { View, Text, Pressable, ScrollView, StyleSheet, Alert, Modal } from 'react-native';
import { useLocalSearchParams, useNavigation, useRouter } from 'expo-router';
import { MoreHorizontal } from 'lucide-react-native';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import * as Burnt from 'burnt';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { userService } from '@/services/user-service';
import { reliabilityService } from '@/services/reliability-service';
import { ReliabilityMeter } from '@/components/reliability-meter';
import { badgeService } from '@/services/badge-service';
import { conversationService } from '@/services/conversation-service';
import { useLayoutEffect, useState } from 'react';
import { UserAvatar } from '@/components/user-avatar';
import { BadgeDisplay } from '@/components/badge-display';
import { SportsBreakdown } from '@/components/sports-breakdown';
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

  useLayoutEffect(() => {
    navigation.setOptions({
      headerRight: () =>
        isOwnProfile ? null : (
          <Pressable onPress={() => setShowMenu(true)} hitSlop={12} style={{ paddingHorizontal: spacing.md }}>
            <MoreHorizontal size={24} color={colors.textPrimary} strokeWidth={2.2} />
          </Pressable>
        ),
    });
  }, [navigation, isOwnProfile]);

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
        <Text style={styles.loadingText}>...</Text>
      </View>
    );
  }


  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <View style={styles.profile}>
        <UserAvatar name={profile.display_name} avatarUrl={profile.avatar_url} size={80} />
        <Text style={styles.name}>{profile.display_name}</Text>
        <View style={styles.reliabilityWrap}>
          <ReliabilityMeter score={stats?.reliability_score ?? null} />
        </View>
        <Text style={styles.memberSince}>
          {t('profil.memberSince', { date: dayjs(profile.created_at).locale(i18n.language).format('MMM YYYY') })}
        </Text>
      </View>

      {/* Stats */}
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

      {/* Sports breakdown */}
      <SportsBreakdown rows={sportBreakdown ?? []} />

      {/* Badges */}
      <BadgeDisplay reputation={reputation ?? []} trophies={trophies ?? []} />

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
  loadingText: { color: colors.textSecondary, fontSize: fontSizes.lg },
  profile: { alignItems: 'center', marginTop: spacing.lg, marginBottom: spacing.xl },
  name: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold', marginTop: spacing.md },
  reliability: { color: colors.textPrimary, fontSize: fontSizes.sm, marginTop: spacing.xs },
  reliabilityWrap: { width: '80%', marginTop: spacing.md },
  memberSince: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: spacing.xs },
  statsRow: {
    flexDirection: 'row', justifyContent: 'space-around',
    backgroundColor: colors.surface, borderRadius: radius.lg,
    paddingVertical: spacing.md, marginBottom: spacing.xl,
    elevation: 3, shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.25, shadowRadius: 4,
  },
  stat: { alignItems: 'center', flex: 1 },
  statDivider: { width: 1, backgroundColor: colors.background, marginVertical: spacing.xs },
  statNumber: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold' },
  statLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: 2, textAlign: 'center' },
  section: { marginBottom: spacing.lg },
  sectionTitle: { color: colors.textPrimary, fontSize: fontSizes.xs, fontWeight: 'bold', letterSpacing: 0.5, textTransform: 'uppercase', marginBottom: spacing.sm },
  sportsTags: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs },
  sportTag: { backgroundColor: colors.surface, borderRadius: radius.full, paddingHorizontal: spacing.sm, paddingVertical: spacing.xs },
  sportTagText: { color: colors.textPrimary, fontSize: fontSizes.xs },
  actions: { marginTop: spacing.lg, gap: spacing.sm },
  messageButton: {
    backgroundColor: colors.cta, borderRadius: radius.full,
    paddingVertical: spacing.md, alignItems: 'center',
  },
  messageText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: 'bold' },
  blockButton: {
    backgroundColor: 'transparent', borderRadius: radius.full,
    paddingVertical: spacing.sm, alignItems: 'center',
  },
  blockText: { color: colors.error, fontSize: fontSizes.sm },
  unblockButton: {
    backgroundColor: 'transparent', borderRadius: radius.full,
    paddingVertical: spacing.sm, alignItems: 'center',
  },
  unblockText: { color: colors.textSecondary, fontSize: fontSizes.sm },
  reportButton: { paddingVertical: spacing.sm, alignItems: 'center', marginTop: spacing.md },
  reportText: { color: colors.textSecondary, fontSize: fontSizes.xs },
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
