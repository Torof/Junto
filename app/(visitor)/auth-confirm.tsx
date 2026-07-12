import { useEffect, useMemo, useState } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { authService } from '@/services/auth-service';
import { useAuthStore } from '@/store/auth-store';
import { LogoSpinner } from '@/components/logo-spinner';

type Phase = 'verifying' | 'invalid';

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
    access_token?: string;
    refresh_token?: string;
    type?: string;
  }>();

  const [phase, setPhase] = useState<Phase>('verifying');

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const tokenHash = typeof params.token_hash === 'string' ? params.token_hash : null;
      const accessToken = typeof params.access_token === 'string' ? params.access_token : null;
      const refreshToken = typeof params.refresh_token === 'string' ? params.refresh_token : null;

      try {
        if (tokenHash) {
          await authService.verifySignupToken(tokenHash);
        } else if (accessToken && refreshToken) {
          await authService.setRecoverySession(accessToken, refreshToken);
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
  }, [params.token_hash, params.access_token, params.refresh_token, router]);

  if (phase === 'invalid') {
    return (
      <View style={[styles.center, { paddingTop: insets.top, paddingBottom: insets.bottom }]}>
        <Text style={styles.title}>{t('auth.confirmInvalidTitle', { defaultValue: 'Lien expiré' })}</Text>
        <Text style={styles.subtitle}>
          {t('auth.confirmInvalidBody', { defaultValue: 'Ce lien de confirmation n\'est plus valide. Connecte-toi avec ton email et ton mot de passe.' })}
        </Text>
        <Pressable style={styles.primaryButton} onPress={() => router.replace('/(visitor)/login')}>
          <Text style={styles.primaryButtonText}>{t('auth.backToLogin', { defaultValue: 'Retour à la connexion' })}</Text>
        </Pressable>
      </View>
    );
  }

  return (
    <View style={[styles.center, { paddingTop: insets.top, paddingBottom: insets.bottom }]}>
      <LogoSpinner />
      <Text style={styles.subtitle}>{t('auth.confirmVerifying', { defaultValue: 'Connexion en cours…' })}</Text>
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
