import { useState } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet, Alert } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import * as Burnt from 'burnt';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { supabase } from '@/services/supabase';
import { activityService } from '@/services/activity-service';
import { reliabilityService } from '@/services/reliability-service';
import { UserAvatar } from '@/components/user-avatar';
import { SettingsDrawer } from '@/components/settings-drawer';
// Lazy import — native module not available until dev build
const pickAndUploadAvatar = () => import('@/utils/avatar-upload').then((m) => m.pickAndUploadAvatar());

export default function ProfilScreen() {
  const { t, i18n } = useTranslation();
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [uploading, setUploading] = useState(false);
  const queryClient = useQueryClient();

  const { data: user } = useQuery({
    queryKey: ['currentUser'],
    queryFn: async () => {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) return null;
      const { data } = await supabase
        .from('users')
        .select('display_name, email, tier, sports, avatar_url, reliability_score, is_admin, created_at, notification_preferences')
        .single();
      return data as { display_name: string; email: string; tier: string; sports: string[]; avatar_url: string | null; reliability_score: number | null; is_admin: boolean; created_at: string; notification_preferences: Record<string, boolean> } | null;
    },
    retry: 2,
  });

  const { data: createdActivities } = useQuery({
    queryKey: ['activities', 'my-created'],
    queryFn: () => activityService.getMyCreated(),
  });

  const { data: joinedActivities } = useQuery({
    queryKey: ['activities', 'my-joined'],
    queryFn: () => activityService.getMyJoined(),
  });

  const completedCount = [
    ...(createdActivities ?? []),
    ...(joinedActivities ?? []),
  ].filter((a) => a.status === 'completed').length;

  const totalCount = (createdActivities?.length ?? 0) + (joinedActivities?.length ?? 0);
  const sports = user?.sports ?? [];

  const handleAvatarPress = async () => {
    if (uploading) return;
    setUploading(true);
    try {
      const url = await pickAndUploadAvatar();
      if (url) {
        await queryClient.invalidateQueries({ queryKey: ['currentUser'] });
        Burnt.toast({ title: t('toast.avatarUpdated'), preset: 'done' });
      }
    } catch {
      Alert.alert(t('auth.error'), t('profil.avatarError'));
    } finally {
      setUploading(false);
    }
  };

  return (
    <>
      <ScrollView style={styles.container} contentContainerStyle={styles.content}>
        {/* Burger menu */}
        <Pressable style={styles.burgerButton} onPress={() => setDrawerOpen(true)}>
          <Text style={styles.burgerIcon}>☰</Text>
        </Pressable>

        {/* Avatar + Name */}
        <View style={styles.profile}>
          <Pressable onPress={handleAvatarPress} disabled={uploading} style={uploading && styles.uploading}>
            <UserAvatar name={user?.display_name ?? '?'} avatarUrl={user?.avatar_url} size={80} />
          </Pressable>
          <Text style={styles.name}>{user?.display_name ?? '...'}</Text>
          <Text style={styles.tier}>{user?.tier ?? 'free'}</Text>
          {user?.reliability_score != null && (
            <Text style={styles.reliability}>
              {reliabilityService.getReliabilityEmoji(user.reliability_score)} {reliabilityService.getReliabilityLabel(user.reliability_score)}
            </Text>
          )}
          {user?.created_at && (
            <Text style={styles.memberSince}>
              {t('profil.memberSince', { date: dayjs(user.created_at).locale(i18n.language).format('MMM YYYY') })}
            </Text>
          )}
        </View>

        {/* Stats */}
        <View style={styles.statsRow}>
          <View style={styles.stat}>
            <Text style={styles.statNumber}>{totalCount}</Text>
            <Text style={styles.statLabel}>{t('profil.activities')}</Text>
          </View>
          <View style={styles.stat}>
            <Text style={styles.statNumber}>{completedCount}</Text>
            <Text style={styles.statLabel}>{t('profil.completed')}</Text>
          </View>
          <View style={styles.stat}>
            <Text style={styles.statNumber}>{sports.length}</Text>
            <Text style={styles.statLabel}>{t('profil.sportsCount')}</Text>
          </View>
        </View>

        {/* Sports */}
        {sports.length > 0 && (
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>{t('profil.sportsLevels')}</Text>
            <View style={styles.sportsTags}>
              {sports.map((sportKey) => (
                <View key={sportKey} style={styles.sportTag}>
                  <Text style={styles.sportTagText}>{t(`sports.${sportKey}`, sportKey)}</Text>
                </View>
              ))}
            </View>
          </View>
        )}
      </ScrollView>

      <SettingsDrawer visible={drawerOpen} onClose={() => setDrawerOpen(false)} />
    </>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.lg, paddingBottom: spacing.xl + 32 },
  burgerButton: {
    alignSelf: 'flex-end',
    width: 40, height: 40,
    alignItems: 'center', justifyContent: 'center',
  },
  burgerIcon: { fontSize: 24, color: colors.textPrimary },
  profile: { alignItems: 'center', marginBottom: spacing.xl },
  uploading: { opacity: 0.5 },
  name: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold', marginTop: spacing.md },
  tier: { color: colors.cta, fontSize: fontSizes.xs, marginTop: spacing.sm, textTransform: 'uppercase' },
  reliability: { color: colors.textPrimary, fontSize: fontSizes.sm, marginTop: spacing.xs },
  memberSince: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: spacing.xs },
  statsRow: {
    flexDirection: 'row', justifyContent: 'space-around',
    backgroundColor: colors.surface, borderRadius: radius.md,
    paddingVertical: spacing.md, marginBottom: spacing.xl,
  },
  stat: { alignItems: 'center' },
  statNumber: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold' },
  statLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: 2 },
  section: { marginBottom: spacing.lg },
  sectionTitle: { color: colors.textSecondary, fontSize: fontSizes.xs, textTransform: 'uppercase', marginBottom: spacing.sm },
  sportsTags: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs },
  sportTag: { backgroundColor: colors.surface, borderRadius: radius.full, paddingHorizontal: spacing.sm, paddingVertical: spacing.xs },
  sportTagText: { color: colors.textPrimary, fontSize: fontSizes.xs },
});
