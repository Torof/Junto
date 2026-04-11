import { useState } from 'react';
import { View, Text, Pressable, Switch, ScrollView, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { authService } from '@/services/auth-service';
import { supabase } from '@/services/supabase';

const NOTIFICATION_TYPES = [
  'join_request',
  'participant_joined',
  'request_accepted',
  'request_refused',
  'participant_removed',
  'participant_left',
  'activity_cancelled',
  'activity_updated',
] as const;

type NotificationPreferences = Record<string, boolean>;

export default function ProfilScreen() {
  const { t } = useTranslation();
  const queryClient = useQueryClient();

  const [showNotifPrefs, setShowNotifPrefs] = useState(false);

  const { data: user } = useQuery({
    queryKey: ['currentUser'],
    queryFn: async () => {
      const { data } = await supabase
        .from('users')
        .select('display_name, email, tier, notification_preferences')
        .single();
      return data as { display_name: string; email: string; tier: string; notification_preferences: NotificationPreferences } | null;
    },
  });

  const prefs = user?.notification_preferences ?? {};

  const togglePref = async (type: string) => {
    const current = prefs[type] !== false;
    const updated = { ...prefs, [type]: !current };
    const userId = (await supabase.auth.getUser()).data.user?.id ?? '';
    await supabase
      .from('users')
      .update({ bio: undefined, notification_preferences: updated } as unknown as { bio: string })
      .eq('id', userId);
    await queryClient.invalidateQueries({ queryKey: ['currentUser'] });
  };

  const handleLogout = async () => {
    await authService.signOut();
  };

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <View style={styles.profile}>
        <View style={styles.avatar}>
          <Text style={styles.initial}>{user?.display_name?.charAt(0)?.toUpperCase() ?? '?'}</Text>
        </View>
        <Text style={styles.name}>{user?.display_name ?? '...'}</Text>
        <Text style={styles.email}>{user?.email ?? ''}</Text>
        <Text style={styles.tier}>{user?.tier ?? 'free'}</Text>
      </View>

      <Pressable style={styles.dropdownHeader} onPress={() => setShowNotifPrefs(!showNotifPrefs)}>
        <Text style={styles.dropdownTitle}>{t('profil.notificationPrefs')}</Text>
        <Text style={styles.dropdownArrow}>{showNotifPrefs ? '▲' : '▼'}</Text>
      </Pressable>

      {showNotifPrefs && (
        <View style={styles.dropdownContent}>
          {NOTIFICATION_TYPES.map((type) => (
            <View key={type} style={styles.prefRow}>
              <Text style={styles.prefLabel}>{t(`profil.notifType.${type}`)}</Text>
              <Switch
                value={prefs[type] !== false}
                onValueChange={() => togglePref(type)}
                trackColor={{ false: colors.surface, true: colors.cta }}
                thumbColor="#fff"
              />
            </View>
          ))}
        </View>
      )}

      <Pressable style={styles.logoutButton} onPress={handleLogout}>
        <Text style={styles.logoutText}>{t('profil.logout')}</Text>
      </Pressable>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  content: {
    padding: spacing.lg,
    paddingBottom: spacing.xl + 32,
  },
  profile: {
    alignItems: 'center',
    marginTop: spacing.xl,
    marginBottom: spacing.xl,
  },
  avatar: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: colors.surface,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: spacing.md,
  },
  initial: {
    color: colors.cta,
    fontSize: fontSizes.xxl,
    fontWeight: 'bold',
  },
  name: {
    color: colors.textPrimary,
    fontSize: fontSizes.xl,
    fontWeight: 'bold',
  },
  email: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
    marginTop: spacing.xs,
  },
  tier: {
    color: colors.cta,
    fontSize: fontSizes.xs,
    marginTop: spacing.sm,
    textTransform: 'uppercase',
  },
  dropdownHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.md,
    marginBottom: spacing.xs,
  },
  dropdownTitle: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: 'bold',
  },
  dropdownArrow: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
  },
  dropdownContent: {
    marginBottom: spacing.lg,
  },
  prefRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    marginBottom: spacing.xs,
  },
  prefLabel: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    flex: 1,
    marginRight: spacing.md,
  },
  logoutButton: {
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    paddingVertical: spacing.md,
    alignItems: 'center',
  },
  logoutText: {
    color: colors.error,
    fontSize: fontSizes.md,
    fontWeight: 'bold',
  },
});
