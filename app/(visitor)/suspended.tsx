import { View, Text, Pressable, StyleSheet, Linking } from 'react-native';
import { useTranslation } from 'react-i18next';
import * as Burnt from 'burnt';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { supabase } from '@/services/supabase';

const SUPPORT_EMAIL = 'support@junto.app';

export default function SuspendedScreen() {
  const { t } = useTranslation();

  const handleLogout = async () => {
    await supabase.auth.signOut();
  };

  const handleContact = () => {
    Linking.openURL(`mailto:${SUPPORT_EMAIL}?subject=${encodeURIComponent(t('suspended.emailSubject'))}`);
  };

  const handleDeleteAccount = () => {
    // TODO: wire to account deletion when built
    Burnt.toast({ title: t('suspended.deleteSoon') });
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

const styles = StyleSheet.create({
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
