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
import { ReliabilityMeter } from '@/components/reliability-meter';
import { UserAvatar } from '@/components/user-avatar';
import { BadgeDisplay } from '@/components/badge-display';
import { SportsBreakdown } from '@/components/sports-breakdown';
import { Camera, Plus } from 'lucide-react-native';
import { getFriendlyError } from '@/utils/friendly-error';
import { SettingsDrawer } from '@/components/settings-drawer';
// Lazy import — native module not available until dev build
const pickAndUploadAvatar = () => import('@/utils/avatar-upload').then((m) => m.pickAndUploadAvatar());

export default function ProfilScreen() {
  const { t, i18n } = useTranslation();
  const navigation = useNavigation();
  const [drawerOpen, setDrawerOpen] = useState(false);

  useLayoutEffect(() => {
    navigation.setOptions({
      headerRight: () => (
        <Pressable onPress={() => setDrawerOpen(true)} hitSlop={12} style={{ paddingHorizontal: spacing.md }}>
          <Menu size={24} color={colors.textPrimary} strokeWidth={2.2} />
        </Pressable>
      ),
    });
  }, [navigation]);
  const [uploading, setUploading] = useState(false);
  const queryClient = useQueryClient();

  const { data: user } = useQuery({
    queryKey: ['currentUser'],
    queryFn: async () => {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) return null;
      const { data } = await supabase
        .from('users')
        .select('id, display_name, email, tier, sports, avatar_url, reliability_score, is_admin, created_at, notification_preferences')
        .single();
      return data as { id: string; display_name: string; email: string; tier: string; sports: string[]; avatar_url: string | null; reliability_score: number | null; is_admin: boolean; created_at: string; notification_preferences: Record<string, boolean> } | null;
    },
    retry: 2,
  });

  const userId = user?.id ?? null;

  const { data: stats, isLoading: statsLoading, error: statsError } = useQuery({
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
        {/* Avatar + Name */}
        <View style={styles.profile}>
          <Pressable onPress={handleAvatarPress} disabled={uploading} style={uploading && styles.uploading}>
            {user?.avatar_url ? (
              <UserAvatar name={user?.display_name ?? '?'} avatarUrl={user.avatar_url} size={80} />
            ) : (
              <View style={styles.uploadPlaceholder}>
                <Camera size={32} color={colors.textSecondary} strokeWidth={2} />
                <View style={styles.plusBadge}>
                  <Plus size={14} color={colors.textPrimary} strokeWidth={3} />
                </View>
              </View>
            )}
          </Pressable>
          <Text style={styles.name}>{user?.display_name ?? '...'}</Text>
          <Text style={styles.tier}>{user?.tier ?? 'free'}</Text>
          <View style={styles.reliabilityWrap}>
            <ReliabilityMeter score={user?.reliability_score ?? null} />
          </View>
          {user?.created_at && (
            <Text style={styles.memberSince}>
              {t('profil.memberSince', { date: dayjs(user.created_at).locale(i18n.language).format('MMM YYYY') })}
            </Text>
          )}
        </View>

        {/* DEBUG — remove after */}
        <View style={{ padding: 8, backgroundColor: '#222', borderRadius: 8, marginBottom: 12 }}>
          <Text style={{ color: '#fff', fontSize: 10 }}>user keys: {user ? Object.keys(user).join(',') : 'null'}</Text>
          <Text style={{ color: '#fff', fontSize: 10 }}>user.id: {String(user?.id)}</Text>
          <Text style={{ color: '#fff', fontSize: 10 }}>userId: {String(userId)}</Text>
          <Text style={{ color: '#fff', fontSize: 10 }}>loading: {String(statsLoading)}</Text>
          <Text style={{ color: '#fff', fontSize: 10 }}>stats: {stats ? JSON.stringify(stats) : 'undefined'}</Text>
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

      </ScrollView>

      <SettingsDrawer visible={drawerOpen} onClose={() => setDrawerOpen(false)} />
    </>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.lg, paddingBottom: spacing.xl + 32 },
  profile: { alignItems: 'center', marginBottom: spacing.xl },
  uploading: { opacity: 0.5 },
  uploadPlaceholder: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: '#6B7280',
    alignItems: 'center',
    justifyContent: 'center',
  },
  plusBadge: {
    position: 'absolute',
    bottom: 0,
    right: 0,
    width: 26,
    height: 26,
    borderRadius: 13,
    backgroundColor: colors.cta,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 2,
    borderColor: colors.background,
  },
  name: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold', marginTop: spacing.md },
  tier: { color: colors.cta, fontSize: fontSizes.xs, marginTop: spacing.sm, textTransform: 'uppercase' },
  reliability: { color: colors.textPrimary, fontSize: fontSizes.sm, marginTop: spacing.xs },
  reliabilityWrap: { width: '80%', marginTop: spacing.md },
  memberSince: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: spacing.xs },
  statsRow: {
    flexDirection: 'row', justifyContent: 'space-around',
    backgroundColor: colors.surface, borderRadius: radius.md,
    paddingVertical: spacing.md, marginBottom: spacing.xl,
  },
  stat: { alignItems: 'center', flex: 1 },
  statDivider: { width: 1, backgroundColor: colors.background, marginVertical: spacing.xs },
  statNumber: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold' },
  statLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: 2, textAlign: 'center' },
  section: { marginBottom: spacing.lg },
  sectionTitle: { color: colors.textSecondary, fontSize: fontSizes.xs, textTransform: 'uppercase', marginBottom: spacing.sm },
  sportsTags: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs },
  sportTag: { backgroundColor: colors.surface, borderRadius: radius.full, paddingHorizontal: spacing.sm, paddingVertical: spacing.xs },
  sportTagText: { color: colors.textPrimary, fontSize: fontSizes.xs },
});
