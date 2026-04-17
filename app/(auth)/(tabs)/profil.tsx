import { useLayoutEffect, useState } from 'react';
import { useNavigation } from 'expo-router';
import { Menu } from 'lucide-react-native';
import { View, Text, Pressable, ScrollView, StyleSheet, Alert } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import * as Burnt from 'burnt';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { supabase } from '@/services/supabase';
import { userService } from '@/services/user-service';
import { badgeService } from '@/services/badge-service';
import { ReliabilityRing } from '@/components/reliability-ring';
import { UserAvatar } from '@/components/user-avatar';
import { BadgeDisplay } from '@/components/badge-display';
import { SportIconGrid } from '@/components/sport-icon-grid';
import { SportsLevelEditor } from '@/components/sports-level-editor';
import { Camera, Plus } from 'lucide-react-native';
import { getFriendlyError } from '@/utils/friendly-error';
import { SettingsDrawer } from '@/components/settings-drawer';
// Lazy import — native module not available until dev build
const pickAndUploadAvatar = () => import('@/utils/avatar-upload').then((m) => m.pickAndUploadAvatar());

export default function ProfilScreen() {
  const { t, i18n } = useTranslation();
  const navigation = useNavigation();
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [sportsEditorOpen, setSportsEditorOpen] = useState(false);
  const [isSavingSports, setIsSavingSports] = useState(false);
  const [uploading, setUploading] = useState(false);
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
    const tierLabel = user?.tier && user.tier !== 'free' ? user.tier : null;
    navigation.setOptions({
      headerTitle: () => (
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
          <Text style={{ color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold' }}>
            {user?.display_name ?? '...'}
          </Text>
          {tierLabel && (
            <View style={{ backgroundColor: colors.cta + '30', borderRadius: 99, paddingHorizontal: 10, paddingVertical: 3 }}>
              <Text style={{ color: colors.cta, fontSize: fontSizes.xs - 1, fontWeight: 'bold', textTransform: 'uppercase' }}>
                {tierLabel}
              </Text>
            </View>
          )}
        </View>
      ),
      headerRight: () => (
        <Pressable onPress={() => setDrawerOpen(true)} hitSlop={12} style={{ paddingHorizontal: spacing.md }}>
          <Menu size={24} color={colors.textPrimary} strokeWidth={2.2} />
        </Pressable>
      ),
    });
  }, [navigation, user?.display_name, user?.tier]);

  const { data: stats } = useQuery({
    queryKey: ['user-stats', userId],
    queryFn: () => userService.getPublicStats(userId ?? ''),
    enabled: !!userId,
  });

  const { data: sportBreakdown } = useQuery({
    queryKey: ['user-sport-breakdown', userId],
    queryFn: () => userService.getSportBreakdown(userId ?? ''),
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

  const handleSaveSports = async (sports: string[], levelsPerSport: Record<string, string>) => {
    setIsSavingSports(true);
    try {
      await userService.updateProfile({ sports, levels_per_sport: levelsPerSport });
      await queryClient.invalidateQueries({ queryKey: ['currentUser'] });
      await queryClient.invalidateQueries({ queryKey: ['user-sport-breakdown'] });
      setSportsEditorOpen(false);
      Burnt.toast({ title: t('profil.save'), preset: 'done' });
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
    } finally {
      setIsSavingSports(false);
    }
  };

  const handleAvatarPress = async () => {
    if (uploading) return;
    setUploading(true);
    try {
      const url = await pickAndUploadAvatar();
      if (url) {
        await queryClient.invalidateQueries({ queryKey: ['currentUser'] });
        Burnt.toast({ title: t('toast.avatarUpdated'), preset: 'done' });
      }
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'uploadAvatar'));
    } finally {
      setUploading(false);
    }
  };

  return (
    <>
      <ScrollView style={styles.container} contentContainerStyle={styles.content}>
        {/* Hero row: avatar + stats */}
        <View style={styles.heroRow}>
          <Pressable onPress={handleAvatarPress} disabled={uploading} style={uploading && styles.uploading}>
            <ReliabilityRing score={user?.reliability_score ?? null} size={110} strokeWidth={3.5}>
              {user?.avatar_url ? (
                <UserAvatar name={user?.display_name ?? '?'} avatarUrl={user.avatar_url} size={110} />
              ) : (
                <View style={styles.uploadPlaceholder}>
                  <Camera size={36} color={colors.textSecondary} strokeWidth={2} />
                  <View style={styles.plusBadge}>
                    <Plus size={14} color={colors.textPrimary} strokeWidth={3} />
                  </View>
                </View>
              )}
            </ReliabilityRing>
          </Pressable>

          <View style={styles.statsColumn}>
            <View style={styles.statsCard}>
              <Text style={styles.statsCardTitle}>{t('profil.activities')}</Text>
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
            {user?.created_at && (
              <Text style={styles.memberSince}>
                {t('profil.memberSince', { date: dayjs(user.created_at).locale(i18n.language).format('MMM YYYY') })}
              </Text>
            )}
          </View>
        </View>

        {/* Sports icon grid */}
        <SportIconGrid
          rows={sportBreakdown ?? []}
          onEdit={() => setSportsEditorOpen(true)}
        />

        {/* Badges */}
        <View style={styles.badgesSection}>
          <Text style={styles.sectionTitle}>{t('profil.badgesSection')}</Text>
          <BadgeDisplay reputation={reputation ?? []} trophies={trophies ?? []} />
        </View>

      </ScrollView>

      <SportsLevelEditor
        visible={sportsEditorOpen}
        sports={user?.sports ?? []}
        levelsPerSport={(user?.levels_per_sport ?? {}) as Record<string, string>}
        onSave={handleSaveSports}
        onClose={() => setSportsEditorOpen(false)}
        isSaving={isSavingSports}
      />
      <SettingsDrawer visible={drawerOpen} onClose={() => setDrawerOpen(false)} />
    </>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.lg, paddingBottom: spacing.xl + 32 },
  heroRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.lg,
    marginBottom: spacing.xl,
  },
  uploading: { opacity: 0.5 },
  uploadPlaceholder: {
    width: 110,
    height: 110,
    borderRadius: 55,
    backgroundColor: '#6B7280',
    alignItems: 'center',
    justifyContent: 'center',
  },
  plusBadge: {
    position: 'absolute',
    bottom: 2,
    right: 2,
    width: 28,
    height: 28,
    borderRadius: 14,
    backgroundColor: colors.cta,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 2,
    borderColor: colors.background,
  },
  statsColumn: {
    flex: 1,
    justifyContent: 'center',
    gap: spacing.sm,
  },
  sectionTitle: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: 'bold',
    letterSpacing: 0.8,
    textTransform: 'uppercase',
    marginBottom: spacing.xs,
  },
  statsCard: {
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.xs,
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
  statsRow: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    alignItems: 'center',
  },
  stat: { alignItems: 'center', flex: 1 },
  statDivider: { width: 1, height: '70%', backgroundColor: colors.background },
  statNumber: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold' },
  statLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: 2, textAlign: 'center' },
  badgesSection: { marginBottom: spacing.lg, marginTop: spacing.sm },
  memberSince: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs - 1,
    textAlign: 'center',
    marginTop: spacing.xs,
    opacity: 0.7,
  },
});
