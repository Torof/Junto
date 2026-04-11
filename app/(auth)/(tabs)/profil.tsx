import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { authService } from '@/services/auth-service';
import { supabase } from '@/services/supabase';

export default function ProfilScreen() {
  const { t } = useTranslation();

  const { data: user } = useQuery({
    queryKey: ['currentUser'],
    queryFn: async () => {
      const { data } = await supabase
        .from('users')
        .select('display_name, email, tier')
        .single();
      return data;
    },
  });

  const handleLogout = async () => {
    await authService.signOut();
  };

  return (
    <View style={styles.container}>
      <View style={styles.profile}>
        <View style={styles.avatar}>
          <Text style={styles.initial}>{user?.display_name?.charAt(0)?.toUpperCase() ?? '?'}</Text>
        </View>
        <Text style={styles.name}>{user?.display_name ?? '...'}</Text>
        <Text style={styles.email}>{user?.email ?? ''}</Text>
        <Text style={styles.tier}>{user?.tier ?? 'free'}</Text>
      </View>

      <Pressable style={styles.logoutButton} onPress={handleLogout}>
        <Text style={styles.logoutText}>{t('profil.logout')}</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
    padding: spacing.lg,
    justifyContent: 'space-between',
  },
  profile: {
    alignItems: 'center',
    marginTop: spacing.xl,
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
  logoutButton: {
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    paddingVertical: spacing.md,
    alignItems: 'center',
    marginBottom: spacing.xl,
  },
  logoutText: {
    color: colors.error,
    fontSize: fontSizes.md,
    fontWeight: 'bold',
  },
});
