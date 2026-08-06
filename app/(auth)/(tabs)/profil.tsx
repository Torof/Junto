import { useLayoutEffect, useState, useMemo, useCallback } from 'react';
import { useFocusEffect, useNavigation, useRouter } from 'expo-router';
import { View, Text, Pressable, ScrollView, StyleSheet, Alert } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import * as Burnt from 'burnt';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { supabase } from '@/services/supabase';
import { userService } from '@/services/user-service';
import { badgeService } from '@/services/badge-service';
import { ProfileHero, reliabilityTierFromScore } from '@/components/profile-hero';
import { ProfileSkeleton } from '@/components/profile-skeleton';
import { BadgeDisplay } from '@/components/badge-display';
import { BadgeCheck, Pencil, QrCode } from 'lucide-react-native';
import { SettingsDrawer } from '@/components/settings-drawer';
import { SportLevelsEditor } from '@/components/sport-levels-editor';
import { getFriendlyError } from '@/utils/friendly-error';
// Lazy import — native module not available until dev build
const pickAndUploadAvatar = () => import('@/utils/avatar-upload').then((m) => m.pickAndUploadAvatar());

export default function ProfilScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t, i18n } = useTranslation();
  const navigation = useNavigation();
  const router = useRouter();
  const [uploading, setUploading] = useState(false);
  // Kept for the header pencil ("edit name") — the settings gear itself moved
  // to the Menu tab's sheet.
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [sportsEditorOpen, setSportsEditorOpen] = useState(false);
  const queryClient = useQueryClient();

  const { data: authId } = useQuery({
    queryKey: ['auth-user-id'],
    queryFn: async () => {
      const { data: { user: authUser } } = await supabase.auth.getUser();
      return authUser?.id ?? null;
    },
  });
  const userId = authId ?? null;

  const { data: user } = useQuery({
    queryKey: ['currentUser', userId],
    queryFn: async () => {
      const { data } = await supabase
        .from('users')
        .select('display_name, email, tier, sports, levels_per_sport, avatar_url, reliability_score, is_admin, created_at, notification_preferences')
        .eq('id', userId!)
        .single();
      return data as { display_name: string; email: string; tier: string; sports: string[]; levels_per_sport: Record<string, string> | null; avatar_url: string | null; reliability_score: number | null; is_admin: boolean; created_at: string; notification_preferences: Record<string, boolean> } | null;
    },
    enabled: !!userId,
    retry: 2,
  });

  useLayoutEffect(() => {
    const tier = user?.tier ?? 'free';
    const badgeColor = tier === 'pro' ? colors.pinMeeting : tier === 'premium' ? colors.pinObjective : null;
    navigation.setOptions({
      headerTitle: () => (
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, paddingLeft: spacing.md }}>
          {badgeColor && (
            <BadgeCheck size={22} color={badgeColor} fill={badgeColor + '50'} strokeWidth={1.5} />
          )}
          <Text style={{ color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold' }}>
            {user?.display_name ?? '...'}
          </Text>
          <Pressable
            onPress={() => setDrawerOpen(true)}
            hitSlop={10}
            accessibilityLabel={t('profil.editName', { defaultValue: 'Edit name' })}
          >
            <Pencil size={14} color={colors.textSecondary} strokeWidth={2} />
          </Pressable>
        </View>
      ),
      headerTitleAlign: 'left' as const,
      headerRight: () => (
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: spacing.sm, paddingRight: spacing.md }}>
          <Pressable
            onPress={() => router.push('/(auth)/my-contact')}
            hitSlop={8}
            accessibilityLabel={t('contactShare.title', { defaultValue: 'Mon contact' })}
          >
            <QrCode size={22} color={colors.textPrimary} strokeWidth={2} />
          </Pressable>
          {tier === 'pro' && userId && (
            <Pressable
              onPress={() => router.push(`/(auth)/pro/${userId}`)}
              hitSlop={8}
              style={styles.proHeaderBtn}
              accessibilityLabel={t('drawer.myProPage', { defaultValue: 'Ma page pro' })}
            >
              <BadgeCheck size={14} color={colors.pinMeeting} fill={colors.pinMeeting + '40'} strokeWidth={2} />
              <Text style={styles.proHeaderText}>{t('drawer.myProPage', { defaultValue: 'Ma page pro' })}</Text>
            </Pressable>
          )}
        </View>
      ),
    });
  }, [navigation, user?.display_name, user?.tier, userId, colors, styles, router, t]);

  // Tab screens never unmount, so their queries never refetch on their own —
  // votes received, level verdicts, stats: everything that changes from
  // ANOTHER device stayed frozen until an app restart. Refetch-on-focus
  // (respecting the 60s staleTime via refetchQueries' stale filter would
  // over-fetch; plain invalidate is fine for these light RPCs).
  useFocusEffect(
    useCallback(() => {
      if (!userId) return;
      for (const key of ['user-stats', 'reputation', 'trophies', 'sport-levels', 'sport-level-votes', 'award-aggregates']) {
        void queryClient.invalidateQueries({ queryKey: [key, userId] });
      }
    }, [userId, queryClient]),
  );

  const { data: stats } = useQuery({
    queryKey: ['user-stats', userId],
    queryFn: () => userService.getPublicStats(userId ?? ''),
    enabled: !!userId,
  });

  const { data: reputation } = useQuery({
    queryKey: ['reputation', userId],
    queryFn: () => badgeService.getUserReputation(userId ?? ''),
    enabled: !!userId,
  });

  const { data: trophies } = useQuery({
    queryKey: ['trophies', userId],
    queryFn: () => badgeService.getUserTrophies(userId ?? ''),
    enabled: !!userId,
  });

  const { data: sportLevels } = useQuery({
    queryKey: ['sport-levels', userId],
    queryFn: () => badgeService.getUserSportLevels(userId ?? ''),
    enabled: !!userId,
  });

  const { data: sportLevelVotes } = useQuery({
    queryKey: ['sport-level-votes', userId],
    queryFn: () => badgeService.getUserSportLevelVotes(userId ?? ''),
    enabled: !!userId,
  });

  const { data: awardAggregates } = useQuery({
    queryKey: ['award-aggregates', userId],
    queryFn: () => badgeService.getUserAwardAggregates(userId ?? ''),
    enabled: !!userId,
  });

  const handleAvatarPress = async () => {
    if (uploading) return;
    setUploading(true);
    try {
      const url = await pickAndUploadAvatar();
      if (url) {
        await queryClient.invalidateQueries({ queryKey: ['currentUser'] });
        // Avatar is rendered everywhere from public_profiles — refresh those
        // caches so the new photo propagates beyond this screen.
        await queryClient.invalidateQueries({ queryKey: ['public-profile'] });
        await queryClient.invalidateQueries({ queryKey: ['participants'] });
        Burnt.toast({ title: t('toast.avatarUpdated'), preset: 'done' });
      }
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'uploadAvatar'));
    } finally {
      setUploading(false);
    }
  };

  // Gate on the user row so the hero doesn't flash empty ('' name, blank
  // avatar, "newcomer" badges) before data lands on cold start.
  if (!user) {
    return <ProfileSkeleton />;
  }

  return (
    <>
      <ScrollView style={styles.container} contentContainerStyle={styles.content}>
        <ProfileHero
          displayName={user?.display_name ?? ''}
          avatarUrl={user?.avatar_url ?? null}
          reliabilityPct={user?.reliability_score ?? null}
          reliabilityTier={user?.reliability_score != null ? reliabilityTierFromScore(user.reliability_score) : null}
          stats={stats ?? null}
          joinedAt={user?.created_at ?? null}
          onAvatarPress={handleAvatarPress}
          isUploading={uploading}
        />

        <BadgeDisplay
          userId={userId ?? ''}
          reputation={reputation ?? []}
          trophies={trophies ?? []}
          sportLevels={sportLevels ?? []}
          sportLevelVotes={sportLevelVotes ?? []}
          awardAggregates={awardAggregates}
          declaredSports={user?.sports ?? []}
          declaredLevels={user?.levels_per_sport ?? null}
          editable
          onEditSports={() => setSportsEditorOpen(true)}
          completedCount={stats?.completed_activities}
          createdCount={stats?.created_activities}
        />

      </ScrollView>

      <SettingsDrawer visible={drawerOpen} onClose={() => setDrawerOpen(false)} />
      <SportLevelsEditor
        visible={sportsEditorOpen}
        onClose={() => setSportsEditorOpen(false)}
        initialLevels={user?.levels_per_sport ?? null}
      />
    </>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.md, paddingBottom: spacing.xl + 32 },
  proHeaderBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    backgroundColor: colors.pinMeeting + '20',
    borderWidth: 1,
    borderColor: colors.pinMeeting,
    borderRadius: radius.full,
    paddingHorizontal: spacing.sm,
    paddingVertical: 3,
  },
  proHeaderText: { color: colors.pinMeeting, fontSize: fontSizes.xs, fontWeight: '800' },
});
