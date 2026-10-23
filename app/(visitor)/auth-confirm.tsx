import { useEffect, useMemo, useState } from 'react';
import { View, Pressable, StyleSheet } from 'react-native';
import { AppText } from '@/components/app-text';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { authService } from '@/services/auth-service';
import { supabase } from '@/services/supabase';
import { useAuthStore } from '@/store/auth-store';
import { LogoSpinner } from '@/components/logo-spinner';

type Phase = 'verifying' | 'invalid' | 'signedIn';

// Signup email confirmation landing — mirror of reset-password. The web
// /auth/callback bridge forwards the confirmation token here via
// junto://auth-confirm so the link logs the user straight into the app
// instead of dropping them on the login screen (Scott 2026-07-12).
export default function AuthConfirmScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const params = useLocalSearchParams<{
    token_hash?: string;
    type?: string;
  }>();

  const [phase, setPhase] = useState<Phase>('verifying');

  useEffect(() => {
    let cancelled = false;
    (async () => {
      // Only the one-time code (see reset-password): raw session tokens in a
      // link are refused (audit L2).
      const tokenHash = typeof params.token_hash === 'string' ? params.token_hash : null;

      // A sign-in link must never silently switch an open session to another
      // account (audit CL-1: a link carrying someone else's tokens would log
      // the victim into the attacker's account). Signed in → refuse.
      const { data: { session: current } } = await supabase.auth.getSession();
      if (current) {
        if (!cancelled) setPhase('signedIn');
        return;
      }

      try {
        if (tokenHash) {
          await authService.verifySignupToken(tokenHash);
        } else {
          if (!cancelled) setPhase('invalid');
          return;
        }
        if (cancelled) return;
        // Session established. A fresh signup always needs onboarding, so
        // go straight there; the root auth gate confirms the same route.
        useAuthStore.getState().triggerRefresh();
        setTimeout(() => router.replace('/(visitor)/onboarding'), 300);
      } catch {
        if (!cancelled) setPhase('invalid');
      }
    })();
    return () => { cancelled = true; };
  }, [params.token_hash, router]);

  if (phase === 'signedIn') {
    return (
      <View style={[styles.center, { paddingTop: insets.top, paddingBottom: insets.bottom }]}>
        <AppText style={styles.title}>{t('auth.linkSignedInTitle', { defaultValue: 'Déjà connecté' })}</AppText>
        <AppText style={styles.subtitle}>{t('auth.linkSignedInBody', { defaultValue: 'Tu es déjà connecté. Déconnecte-toi avant d\'utiliser ce lien.' })}</AppText>
        <Pressable style={styles.primaryButton} onPress={() => router.replace('/')}>
          <AppText style={styles.primaryButtonText}>{t('auth.linkSignedInBack', { defaultValue: 'Retour à l\'app' })}</AppText>
        </Pressable>
      </View>
    );
  }

  if (phase === 'invalid') {
    return (
      <View style={[styles.center, { paddingTop: insets.top, paddingBottom: insets.bottom }]}>
        <AppText style={styles.title}>{t('auth.confirmInvalidTitle', { defaultValue: 'Lien expiré' })}</AppText>
        <AppText style={styles.subtitle}>
          {t('auth.confirmInvalidBody', { defaultValue: 'Ce lien de confirmation n\'est plus valide. Connecte-toi avec ton email et ton mot de passe.' })}
        </AppText>
        <Pressable style={styles.primaryButton} onPress={() => router.replace('/(visitor)/login')}>
          <AppText style={styles.primaryButtonText}>{t('auth.backToLogin', { defaultValue: 'Retour à la connexion' })}</AppText>
        </Pressable>
      </View>
    );
  }

  return (
    <View style={[styles.center, { paddingTop: insets.top, paddingBottom: insets.bottom }]}>
      <LogoSpinner />
      <AppText style={styles.subtitle}>{t('auth.confirmVerifying', { defaultValue: 'Connexion en cours…' })}</AppText>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: spacing.xl, gap: spacing.md, backgroundColor: colors.background },
  title: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: '800', textAlign: 'center' },
  subtitle: { color: colors.textSecondary, fontSize: fontSizes.md, textAlign: 'center', lineHeight: 22 },
  primaryButton: {
    marginTop: spacing.md,
    backgroundColor: colors.cta,
    borderRadius: radius.lg,
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.xl,
    alignItems: 'center',
  },
  primaryButtonText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '800' },
});
