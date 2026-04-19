import { useMemo } from 'react';
import { View, Text, Pressable, StyleSheet, Linking, Alert } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { supabase } from '@/services/supabase';

const SUPPORT_EMAIL = 'support@junto.app';

export default function SuspendedScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();

  const handleLogout = async () => {
    await supabase.auth.signOut();
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
                  await supabase.rpc('delete_own_account' as 'accept_tos');
                  await supabase.auth.signOut();
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
      <Text style={styles.icon}>🚫</Text>
      <Text style={styles.title}>{t('suspended.title')}</Text>
      <Text style={styles.message}>{t('suspended.message')}</Text>

      <Pressable style={styles.contactButton} onPress={handleContact}>
        <Text style={styles.contactText}>{t('suspended.contact')}</Text>
      </Pressable>

      <Pressable style={styles.deleteButton} onPress={handleDeleteAccount}>
        <Text style={styles.deleteText}>{t('suspended.deleteAccount')}</Text>
      </Pressable>

      <Pressable style={styles.logoutButton} onPress={handleLogout}>
        <Text style={styles.logoutText}>{t('profil.logout')}</Text>
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
  contactButton: { backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.md, paddingHorizontal: spacing.xl, marginBottom: spacing.md, width: '100%', alignItems: 'center' },
  contactText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
  deleteButton: { paddingVertical: spacing.sm, marginBottom: spacing.lg },
  deleteText: { color: colors.error, fontSize: fontSizes.sm },
  logoutButton: { paddingVertical: spacing.sm },
  logoutText: { color: colors.textSecondary, fontSize: fontSizes.sm },
});
