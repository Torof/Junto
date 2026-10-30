import { useMemo } from 'react';
import { View, Pressable, StyleSheet, Linking, Alert } from 'react-native';
import { AppText } from '@/components/app-text';
import { useTranslation } from 'react-i18next';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { supabase } from '@/services/supabase';
import { authService } from '@/services/auth-service';

const SUPPORT_EMAIL = 'contact@askandgo.io';

export default function SuspendedScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();

  const handleLogout = async () => {
    await authService.signOut();
  };

  const handleContact = () => {
    Linking.openURL(`mailto:${SUPPORT_EMAIL}?subject=${encodeURIComponent(t('suspended.emailSubject'))}`);
  };

  const handleDeleteAccount = () => {
    Alert.alert(t('account.deleteTitle'), t('account.deleteMessage'), [
      { text: t('activity.no'), style: 'cancel' },
      {
        text: t('account.deleteConfirm'),
        style: 'destructive',
        onPress: () => {
          Alert.alert(t('account.deleteTitle2'), t('account.deleteMessage2'), [
            { text: t('activity.no'), style: 'cancel' },
            {
              text: t('account.deleteFinal'),
              style: 'destructive',
              onPress: async () => {
                try {
                  // The full deletion (auth account + files), like the settings
                  // drawer — the bare RPC left the login alive (audit, re-secure).
                  const { error } = await supabase.functions.invoke('delete-account', { method: 'POST' });
                  if (error) throw error;
                  await authService.signOut();
                } catch {
                  Alert.alert(t('auth.error'), t('auth.unknownError'));
                }
              },
            },
          ]);
        },
      },
    ]);
  };

  return (
    <View style={styles.container}>
      <AppText style={styles.icon}>🚫</AppText>
      <AppText style={styles.title}>{t('suspended.title')}</AppText>
      <AppText style={styles.message}>{t('suspended.message')}</AppText>

      <Pressable style={styles.contactButton} onPress={handleContact}>
        <AppText style={styles.contactText}>{t('suspended.contact')}</AppText>
      </Pressable>

      <Pressable style={styles.deleteButton} onPress={handleDeleteAccount}>
        <AppText style={styles.deleteText}>{t('suspended.deleteAccount')}</AppText>
      </Pressable>

      <Pressable style={styles.logoutButton} onPress={handleLogout}>
        <AppText style={styles.logoutText}>{t('profil.logout')}</AppText>
      </Pressable>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
    alignItems: 'center',
    justifyContent: 'center',
    padding: spacing.xl,
  },
  icon: { fontSize: 48, marginBottom: spacing.lg },
  title: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold', textAlign: 'center', marginBottom: spacing.md },
  message: { color: colors.textSecondary, fontSize: fontSizes.md, textAlign: 'center', lineHeight: 22, marginBottom: spacing.xl },
  contactButton: { backgroundColor: colors.brand, borderRadius: radius.md, paddingVertical: spacing.md, paddingHorizontal: spacing.xl, marginBottom: spacing.md, width: '100%', alignItems: 'center' },
  contactText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
  deleteButton: { paddingVertical: spacing.sm, marginBottom: spacing.lg },
  deleteText: { color: colors.error, fontSize: fontSizes.sm },
  logoutButton: { paddingVertical: spacing.sm },
  logoutText: { color: colors.textSecondary, fontSize: fontSizes.sm },
});
