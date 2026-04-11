import { View, Text, Pressable, ScrollView, StyleSheet, Alert } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import * as Burnt from 'burnt';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { userService } from '@/services/user-service';
import { supabase } from '@/services/supabase';

export default function PublicProfileScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { t } = useTranslation();
  const router = useRouter();
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

  const { data: isBlocked } = useQuery({
    queryKey: ['is-blocked', id],
    queryFn: () => userService.isBlocked(id ?? ''),
    enabled: !!id && !isOwnProfile,
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

  const sports = profile.sports ?? [];

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <View style={styles.profile}>
        <View style={styles.avatar}>
          <Text style={styles.initial}>{profile.display_name.charAt(0).toUpperCase()}</Text>
        </View>
        <Text style={styles.name}>{profile.display_name}</Text>
        <Text style={styles.memberSince}>
          {t('profil.memberSince', { date: dayjs(profile.created_at).format('MMM YYYY') })}
        </Text>
      </View>

      {/* Stats */}
      <View style={styles.statsRow}>
        <View style={styles.stat}>
          <Text style={styles.statNumber}>{stats?.total_activities ?? 0}</Text>
          <Text style={styles.statLabel}>{t('profil.activities')}</Text>
        </View>
        <View style={styles.stat}>
          <Text style={styles.statNumber}>{stats?.completed_activities ?? 0}</Text>
          <Text style={styles.statLabel}>{t('profil.completed')}</Text>
        </View>
        <View style={styles.stat}>
          <Text style={styles.statNumber}>{stats?.sports_count ?? 0}</Text>
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

      {/* Actions (not on own profile) */}
      {!isOwnProfile && (
        <View style={styles.actions}>
          <Pressable style={styles.messageButton} onPress={() => Burnt.toast({ title: t('publicProfile.messageSoon') })}>
            <Text style={styles.messageText}>{t('publicProfile.sendMessage')}</Text>
          </Pressable>

          {isBlocked ? (
            <Pressable style={styles.unblockButton} onPress={handleUnblock}>
              <Text style={styles.unblockText}>{t('publicProfile.unblock')}</Text>
            </Pressable>
          ) : (
            <Pressable style={styles.blockButton} onPress={handleBlock}>
              <Text style={styles.blockText}>{t('publicProfile.block')}</Text>
            </Pressable>
          )}
        </View>
      )}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.lg, paddingBottom: spacing.xl + 32 },
  center: { flex: 1, backgroundColor: colors.background, alignItems: 'center', justifyContent: 'center' },
  loadingText: { color: colors.textSecondary, fontSize: fontSizes.lg },
  profile: { alignItems: 'center', marginTop: spacing.lg, marginBottom: spacing.xl },
  avatar: {
    width: 80, height: 80, borderRadius: 40, backgroundColor: colors.surface,
    alignItems: 'center', justifyContent: 'center', marginBottom: spacing.md,
  },
  initial: { color: colors.cta, fontSize: fontSizes.xxl, fontWeight: 'bold' },
  name: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold' },
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
  actions: { marginTop: spacing.lg, gap: spacing.sm },
  messageButton: {
    backgroundColor: colors.cta, borderRadius: radius.md,
    paddingVertical: spacing.md, alignItems: 'center',
  },
  messageText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: 'bold' },
  blockButton: {
    backgroundColor: 'transparent', borderRadius: radius.md,
    paddingVertical: spacing.sm, alignItems: 'center',
  },
  blockText: { color: colors.error, fontSize: fontSizes.sm },
  unblockButton: {
    backgroundColor: 'transparent', borderRadius: radius.md,
    paddingVertical: spacing.sm, alignItems: 'center',
  },
  unblockText: { color: colors.textSecondary, fontSize: fontSizes.sm },
});
