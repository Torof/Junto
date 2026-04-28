import { useEffect, useMemo, useState } from 'react';
import { View, Text, TextInput, Pressable, StyleSheet, KeyboardAvoidingView, Platform } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { Eye, EyeOff } from 'lucide-react-native';
import * as Burnt from 'burnt';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { authService } from '@/services/auth-service';
import { LogoSpinner } from '@/components/logo-spinner';

type Phase = 'verifying' | 'ready' | 'invalid' | 'submitting';

export default function ResetPasswordScreen() {
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
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const tokenHash = typeof params.token_hash === 'string' ? params.token_hash : null;
      const accessToken = typeof params.access_token === 'string' ? params.access_token : null;
      const refreshToken = typeof params.refresh_token === 'string' ? params.refresh_token : null;

      try {
        if (tokenHash) {
          await authService.verifyRecoveryToken(tokenHash);
        } else if (accessToken && refreshToken) {
          await authService.setRecoverySession(accessToken, refreshToken);
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
  }, [params.token_hash, params.access_token, params.refresh_token]);

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
      setError(err instanceof Error ? err.message : t('auth.unknownError'));
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

  if (phase === 'invalid') {
    return (
      <View style={[styles.center, { paddingTop: insets.top, paddingBottom: insets.bottom }]}>
        <Text style={styles.title}>{t('auth.resetInvalidTitle')}</Text>
        <Text style={styles.subtitle}>{t('auth.resetInvalidBody')}</Text>
        <Pressable style={styles.primaryButton} onPress={() => router.replace('/(visitor)/login')}>
          <Text style={styles.primaryButtonText}>{t('auth.backToLogin')}</Text>
        </Pressable>
      </View>
    );
  }

  return (
    <KeyboardAvoidingView style={styles.container} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <View style={[styles.content, { paddingTop: insets.top + spacing.xl, paddingBottom: insets.bottom + spacing.xl }]}>
        <Text style={styles.title}>{t('auth.resetTitle')}</Text>
        <Text style={styles.subtitle}>{t('auth.resetSubtitle')}</Text>

        <View style={styles.passwordRow}>
          <TextInput
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

        <TextInput
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

        {error && <Text style={styles.errorText}>{error}</Text>}

        <Pressable
          style={[styles.primaryButton, phase === 'submitting' && styles.buttonDisabled]}
          onPress={handleSubmit}
          disabled={phase === 'submitting'}
        >
          <Text style={styles.primaryButtonText}>
            {phase === 'submitting' ? '...' : t('auth.updatePassword')}
          </Text>
        </Pressable>
      </View>
    </KeyboardAvoidingView>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: spacing.xl, backgroundColor: colors.background },
  content: { flex: 1, justifyContent: 'center', paddingHorizontal: spacing.xl },
  title: {
    color: colors.textPrimary, fontSize: fontSizes.xxl, fontWeight: '800',
    textAlign: 'center', marginBottom: spacing.xs,
  },
  subtitle: {
    color: colors.textSecondary, fontSize: fontSizes.md,
    textAlign: 'center', marginBottom: spacing.xl,
  },
  input: {
    backgroundColor: colors.surface, color: colors.textPrimary,
    borderRadius: radius.md, paddingHorizontal: spacing.md, paddingVertical: spacing.md,
    fontSize: fontSizes.md, marginBottom: spacing.md,
  },
  inputFlex: { flex: 1, marginBottom: 0 },
  passwordRow: {
    flexDirection: 'row', alignItems: 'center',
    backgroundColor: colors.surface, borderRadius: radius.md,
    paddingRight: spacing.sm, marginBottom: spacing.md,
  },
  eyeButton: { padding: spacing.xs, paddingHorizontal: spacing.sm },
  errorText: {
    color: colors.error, fontSize: fontSizes.sm, marginBottom: spacing.sm, textAlign: 'center',
  },
  primaryButton: {
    backgroundColor: colors.cta, borderRadius: radius.md,
    paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.sm,
  },
  buttonDisabled: { opacity: 0.6 },
  primaryButtonText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '800' },
});
