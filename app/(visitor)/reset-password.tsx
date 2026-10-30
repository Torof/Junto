import { useEffect, useMemo, useState } from 'react';
import { View, Pressable, StyleSheet } from 'react-native';
import { AppText, AppTextInput } from '@/components/app-text';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { Eye, EyeOff } from 'lucide-react-native';
import * as Burnt from 'burnt';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { KeyboardAwareScrollView } from '@/components/keyboard-aware-scroll-view';
import type { AppColors } from '@/constants/colors';
import { authService } from '@/services/auth-service';
import { supabase } from '@/services/supabase';
import { LogoSpinner } from '@/components/logo-spinner';
import { getFriendlyError } from '@/utils/friendly-error';

type Phase = 'verifying' | 'ready' | 'invalid' | 'submitting' | 'signedIn';

export default function ResetPasswordScreen() {
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
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      // Only the one-time code (email templates use {{ .TokenHash }} since
      // 2026-10-23): a link carrying raw session tokens is refused, so nobody
      // can drop someone else's session into this device (audit L2).
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
          await authService.verifyRecoveryToken(tokenHash);
        } else {
          if (!cancelled) setPhase('invalid');
          return;
        }
        if (!cancelled) setPhase('ready');
      } catch {
        if (!cancelled) setPhase('invalid');
      }
    })();
    return () => { cancelled = true; };
  }, [params.token_hash]);

  const handleSubmit = async () => {
    setError(null);
    if (password.length < 8) {
      setError(t('auth.errPasswordTooShort'));
      return;
    }
    if (password !== confirm) {
      setError(t('auth.errPasswordsMismatch'));
      return;
    }
    setPhase('submitting');
    try {
      await authService.updatePassword(password);
      await authService.signOut();
      Burnt.toast({ title: t('auth.passwordUpdated'), preset: 'done' });
      router.replace('/(visitor)/login');
    } catch (err) {
      setError(getFriendlyError(err, 'generic'));
      setPhase('ready');
    }
  };

  if (phase === 'verifying') {
    return (
      <View style={[styles.center, { paddingTop: insets.top, paddingBottom: insets.bottom }]}>
        <LogoSpinner />
      </View>
    );
  }

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
        <AppText style={styles.title}>{t('auth.resetInvalidTitle')}</AppText>
        <AppText style={styles.subtitle}>{t('auth.resetInvalidBody')}</AppText>
        <Pressable style={styles.primaryButton} onPress={() => router.replace('/(visitor)/login')}>
          <AppText style={styles.primaryButtonText}>{t('auth.backToLogin')}</AppText>
        </Pressable>
      </View>
    );
  }

  return (
    <KeyboardAwareScrollView
      style={styles.container}
      contentContainerStyle={[styles.content, { paddingTop: insets.top + spacing.xl, paddingBottom: insets.bottom + spacing.xl }]}
      restBottom={insets.bottom}
    >
        <AppText style={styles.title}>{t('auth.resetTitle')}</AppText>
        <AppText style={styles.subtitle}>{t('auth.resetSubtitle')}</AppText>

        <View style={styles.passwordRow}>
          <AppTextInput
            style={[styles.input, styles.inputFlex]}
            placeholder={t('auth.newPassword')}
            placeholderTextColor={colors.textSecondary}
            value={password}
            onChangeText={(v) => { setPassword(v); setError(null); }}
            secureTextEntry={!showPassword}
            autoCapitalize="none"
            autoComplete="new-password"
            returnKeyType="next"
          />
          <Pressable style={styles.eyeButton} onPress={() => setShowPassword((s) => !s)}>
            {showPassword ? <EyeOff size={20} color={colors.textSecondary} /> : <Eye size={20} color={colors.textSecondary} />}
          </Pressable>
        </View>

        <AppTextInput
          style={styles.input}
          placeholder={t('auth.confirmPassword')}
          placeholderTextColor={colors.textSecondary}
          value={confirm}
          onChangeText={(v) => { setConfirm(v); setError(null); }}
          secureTextEntry={!showPassword}
          autoCapitalize="none"
          autoComplete="new-password"
          returnKeyType="done"
          onSubmitEditing={handleSubmit}
        />

        {error && <AppText style={styles.errorText}>{error}</AppText>}

        <Pressable
          style={[styles.primaryButton, phase === 'submitting' && styles.buttonDisabled]}
          onPress={handleSubmit}
          disabled={phase === 'submitting'}
        >
          <AppText style={styles.primaryButtonText}>
            {phase === 'submitting' ? '...' : t('auth.updatePassword')}
          </AppText>
        </Pressable>
    </KeyboardAwareScrollView>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: spacing.xl, backgroundColor: colors.background },
  content: { flexGrow: 1, justifyContent: 'center', paddingHorizontal: spacing.xl },
  title: {
    color: colors.textPrimary, fontSize: fontSizes.xxl, fontWeight: '800',
    textAlign: 'center', marginBottom: spacing.xs,
  },
  subtitle: {
    color: colors.textSecondary, fontSize: fontSizes.md,
    textAlign: 'center', marginBottom: spacing.xl,
  },
  input: { borderWidth: 1, borderColor: colors.lineStrong,
    backgroundColor: colors.surfaceAlt, color: colors.textPrimary,
    borderRadius: radius.md, paddingHorizontal: spacing.md, paddingVertical: spacing.md,
    fontSize: fontSizes.md, marginBottom: spacing.md,
  },
  inputFlex: { flex: 1, marginBottom: 0 },
  passwordRow: { borderWidth: 1, borderColor: colors.lineStrong,
    flexDirection: 'row', alignItems: 'center',
    backgroundColor: colors.surfaceAlt, borderRadius: radius.md,
    paddingRight: spacing.sm, marginBottom: spacing.md,
  },
  eyeButton: { padding: spacing.xs, paddingHorizontal: spacing.sm },
  errorText: {
    color: colors.error, fontSize: fontSizes.sm, marginBottom: spacing.sm, textAlign: 'center',
  },
  primaryButton: {
    backgroundColor: colors.brand, borderRadius: radius.md,
    paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.sm,
  },
  buttonDisabled: { opacity: 0.6 },
  primaryButtonText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '800' },
});
