import { useState } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { supabase } from '@/services/supabase';
import { activityService } from '@/services/activity-service';
import { SettingsDrawer } from '@/components/settings-drawer';

export default function ProfilScreen() {
  const { t } = useTranslation();
  const [drawerOpen, setDrawerOpen] = useState(false);

  const { data: user } = useQuery({
    queryKey: ['currentUser'],
    queryFn: async () => {
      const { data } = await supabase
        .from('users')
        .select('display_name, tier, sports, created_at')
        .single();
      return data as { display_name: string; tier: string; sports: string[]; created_at: string } | null;
    },
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

  return (
    <>
      <ScrollView style={styles.container} contentContainerStyle={styles.content}>
        {/* Burger menu */}
        <Pressable style={styles.burgerButton} onPress={() => setDrawerOpen(true)}>
          <Text style={styles.burgerIcon}>☰</Text>
        </Pressable>

        {/* Avatar + Name */}
        <View style={styles.profile}>
          <View style={styles.avatar}>
            <Text style={styles.initial}>{user?.display_name?.charAt(0)?.toUpperCase() ?? '?'}</Text>
          </View>
          <Text style={styles.name}>{user?.display_name ?? '...'}</Text>
          <Text style={styles.tier}>{user?.tier ?? 'free'}</Text>
          {user?.created_at && (
            <Text style={styles.memberSince}>
              {t('profil.memberSince', { date: dayjs(user.created_at).format('MMM YYYY') })}
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
  avatar: {
    width: 80, height: 80, borderRadius: 40, backgroundColor: colors.surface,
    alignItems: 'center', justifyContent: 'center', marginBottom: spacing.md,
  },
  initial: { color: colors.cta, fontSize: fontSizes.xxl, fontWeight: 'bold' },
  name: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold' },
  tier: { color: colors.cta, fontSize: fontSizes.xs, marginTop: spacing.sm, textTransform: 'uppercase' },
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
