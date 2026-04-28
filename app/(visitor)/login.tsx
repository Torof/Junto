import { useState, useMemo } from 'react';
import {
  View, Text, TextInput, Pressable, ScrollView, StyleSheet,
  Image, KeyboardAvoidingView, Platform,
} from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Svg, { Path, G, Rect } from 'react-native-svg';
import { Eye, EyeOff, Check } from 'lucide-react-native';
import * as Burnt from 'burnt';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { authService } from '@/services/auth-service';

type Mode = 'login' | 'register' | 'forgot';

export default function LoginScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const insets = useSafeAreaInsets();

  const [mode, setMode] = useState<Mode>('login');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [tosAccepted, setTosAccepted] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const friendlyAuthError = (raw: string): string => {
    const m = raw.toLowerCase();
    if (m.includes('invalid login credentials')) return t('auth.errInvalidCredentials');
    if (m.includes('email not confirmed')) return t('auth.errEmailNotConfirmed');
    if (m.includes('user already registered') || m.includes('already been registered')) return t('auth.errEmailTaken');
    if (m.includes('password should be at least')) return t('auth.errPasswordTooShort');
    if (m.includes('unable to validate email') || m.includes('invalid email')) return t('auth.errInvalidEmail');
    if (m.includes('rate limit') || m.includes('too many requests')) return t('auth.errRateLimit');
    if (m.includes('network')) return t('auth.errNetwork');
    return t('auth.unknownError');
  };

  const switchMode = (next: Mode) => {
    setMode(next);
    setError(null);
    setPassword('');
  };

  const handleSubmit = async () => {
    setError(null);
    const trimmedEmail = email.trim();
    if (!trimmedEmail) {
      setError(t('auth.errInvalidEmail'));
      return;
    }
    if (mode !== 'forgot' && !password.trim()) {
      setError(t('auth.errPasswordTooShort'));
      return;
    }
    if (mode === 'register' && !tosAccepted) {
      setError(t('auth.errTosRequired'));
      return;
    }
    setIsLoading(true);
    try {
      if (mode === 'login') {
        await authService.signInWithEmail(trimmedEmail, password);
      } else if (mode === 'register') {
        await authService.signUpWithEmail(trimmedEmail, password);
        Burnt.toast({ title: t('auth.confirmationSent'), preset: 'done' });
      } else {
        await authService.requestPasswordReset(trimmedEmail);
        Burnt.toast({ title: t('auth.resetEmailSent'), preset: 'done' });
        switchMode('login');
      }
    } catch (err) {
      const raw = err instanceof Error ? err.message : t('auth.unknownError');
      setError(friendlyAuthError(raw));
    } finally {
      setIsLoading(false);
    }
  };

  const ctaLabel =
    mode === 'login' ? t('auth.login')
    : mode === 'register' ? t('auth.register')
    : t('auth.sendReset');

  return (
    <KeyboardAvoidingView style={styles.container} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView
        contentContainerStyle={[
          styles.scroll,
          { paddingTop: insets.top + spacing.xl, paddingBottom: insets.bottom + spacing.xl },
        ]}
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode="on-drag"
      >
        <View style={styles.content}>
        <Svg
          style={StyleSheet.absoluteFill}
          viewBox="0 0 600 1000"
          preserveAspectRatio="xMidYMid slice"
          pointerEvents="none"
        >
          <Rect width={600} height={1000} fill="transparent" />
          <G fill="none" stroke={colors.textPrimary} strokeWidth={0.6} opacity={0.06}>
            {Array.from({ length: 26 }).map((_, i) => (
              <Path
                key={i}
                d={`M 0 ${30 + i * 38} Q 150 ${20 + i * 38} 300 ${33 + i * 38} T 600 ${27 + i * 38}`}
              />
            ))}
          </G>
        </Svg>

        <View style={styles.header}>
          <Image source={require('../../assets/junto_icon_square.png')} style={styles.logo} />
          <Text style={styles.brand}>{t('app.name')}</Text>
          <Text style={styles.tagline}>{t('auth.tagline')}</Text>
        </View>

        {mode !== 'forgot' && (
          <View style={styles.tabs}>
            <Pressable
              style={[styles.tab, mode === 'login' && styles.tabActive]}
              onPress={() => switchMode('login')}
            >
              <Text style={[styles.tabText, mode === 'login' && styles.tabTextActive]}>
                {t('auth.signIn')}
              </Text>
            </Pressable>
            <Pressable
              style={[styles.tab, mode === 'register' && styles.tabActive]}
              onPress={() => switchMode('register')}
            >
              <Text style={[styles.tabText, mode === 'register' && styles.tabTextActive]}>
                {t('auth.createAccount')}
              </Text>
            </Pressable>
          </View>
        )}

        {mode === 'forgot' && (
          <View style={styles.forgotHeader}>
            <Text style={styles.forgotTitle}>{t('auth.forgotTitle')}</Text>
            <Text style={styles.forgotSubtitle}>{t('auth.forgotSubtitle')}</Text>
          </View>
        )}

        <TextInput
          style={styles.input}
          placeholder={t('auth.email')}
          placeholderTextColor={colors.textSecondary}
          value={email}
          onChangeText={(v) => { setEmail(v); setError(null); }}
          keyboardType="email-address"
          autoCapitalize="none"
          autoComplete="email"
          returnKeyType={mode === 'forgot' ? 'send' : 'next'}
          onSubmitEditing={mode === 'forgot' ? handleSubmit : undefined}
        />

        {mode !== 'forgot' && (
          <View style={styles.passwordRow}>
            <TextInput
              style={[styles.input, styles.inputFlex]}
              placeholder={t('auth.password')}
              placeholderTextColor={colors.textSecondary}
              value={password}
              onChangeText={(v) => { setPassword(v); setError(null); }}
              secureTextEntry={!showPassword}
              autoCapitalize="none"
              autoComplete={mode === 'register' ? 'new-password' : 'current-password'}
              returnKeyType="done"
              onSubmitEditing={handleSubmit}
            />
            <Pressable style={styles.eyeButton} onPress={() => setShowPassword((s) => !s)}>
              {showPassword
                ? <EyeOff size={20} color={colors.textSecondary} />
                : <Eye size={20} color={colors.textSecondary} />}
            </Pressable>
          </View>
        )}

        {mode === 'register' && (
          <Pressable style={styles.tosRow} onPress={() => setTosAccepted((v) => !v)}>
            <View style={[styles.checkbox, tosAccepted && styles.checkboxChecked]}>
              {tosAccepted && <Check size={14} color={colors.textPrimary} strokeWidth={3} />}
            </View>
            <Text style={styles.tosText}>
              {t('auth.tosPrefix')}{' '}
              <Text style={styles.link} onPress={() => router.push('/(visitor)/legal/terms')}>
                {t('auth.tosTerms')}
              </Text>
              {t('auth.tosAnd')}
              <Text style={styles.link} onPress={() => router.push('/(visitor)/legal/privacy')}>
                {t('auth.tosPrivacy')}
              </Text>
            </Text>
          </Pressable>
        )}

        {error && <Text style={styles.errorText}>{error}</Text>}

        <Pressable
          style={[styles.primaryButton, isLoading && styles.buttonDisabled]}
          onPress={handleSubmit}
          disabled={isLoading}
        >
          <Text style={styles.primaryButtonText}>{isLoading ? '...' : ctaLabel}</Text>
        </Pressable>

        {mode === 'login' && (
          <Pressable onPress={() => switchMode('forgot')} style={styles.linkRow}>
            <Text style={styles.linkText}>{t('auth.forgotPassword')}</Text>
          </Pressable>
        )}

        {mode === 'forgot' && (
          <Pressable onPress={() => switchMode('login')} style={styles.linkRow}>
            <Text style={styles.linkText}>{t('auth.backToLogin')}</Text>
          </Pressable>
        )}
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  scroll: { flexGrow: 1, paddingHorizontal: spacing.xl },
  content: { flex: 1, justifyContent: 'center' },

  header: { alignItems: 'center', marginBottom: spacing.xl },
  logo: { width: 76, height: 76, marginBottom: spacing.md, borderRadius: 18 },
  brand: { color: colors.textPrimary, fontSize: 32, fontWeight: '800', letterSpacing: -0.5 },
  tagline: { color: colors.textSecondary, fontSize: fontSizes.sm, marginTop: 4 },

  tabs: {
    flexDirection: 'row',
    backgroundColor: colors.surface,
    borderRadius: 999,
    padding: 4,
    marginBottom: spacing.lg,
    borderWidth: 1, borderColor: colors.line,
  },
  tab: { flex: 1, paddingVertical: 10, alignItems: 'center', borderRadius: 999 },
  tabActive: { backgroundColor: colors.cta },
  tabText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '700' },
  tabTextActive: { color: colors.textPrimary, fontWeight: '800' },

  forgotHeader: { marginBottom: spacing.lg, alignItems: 'center' },
  forgotTitle: {
    color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800', marginBottom: 4,
  },
  forgotSubtitle: {
    color: colors.textSecondary, fontSize: fontSizes.sm, textAlign: 'center', lineHeight: 18,
  },

  input: {
    backgroundColor: colors.surface, color: colors.textPrimary,
    borderRadius: radius.md, paddingHorizontal: spacing.md, paddingVertical: spacing.md,
    fontSize: fontSizes.md, marginBottom: spacing.md,
    borderWidth: 1, borderColor: colors.line,
  },
  inputFlex: { flex: 1, marginBottom: 0, borderWidth: 0 },
  passwordRow: {
    flexDirection: 'row', alignItems: 'center',
    backgroundColor: colors.surface, borderRadius: radius.md,
    paddingRight: spacing.sm, marginBottom: spacing.md,
    borderWidth: 1, borderColor: colors.line,
  },
  eyeButton: { padding: spacing.xs, paddingHorizontal: spacing.sm },

  tosRow: {
    flexDirection: 'row', alignItems: 'flex-start',
    gap: spacing.sm, marginBottom: spacing.md,
  },
  checkbox: {
    width: 22, height: 22, borderRadius: 6,
    borderWidth: 1.5, borderColor: colors.line,
    alignItems: 'center', justifyContent: 'center',
    backgroundColor: colors.surface, marginTop: 1,
  },
  checkboxChecked: { backgroundColor: colors.cta, borderColor: colors.cta },
  tosText: {
    color: colors.textSecondary, fontSize: fontSizes.sm, flex: 1, lineHeight: 18,
  },
  link: { color: colors.cta, fontWeight: '700' },

  errorText: {
    color: colors.error, fontSize: fontSizes.sm,
    textAlign: 'center', marginBottom: spacing.sm,
  },

  primaryButton: {
    backgroundColor: colors.cta, borderRadius: radius.md,
    paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.xs,
  },
  buttonDisabled: { opacity: 0.6 },
  primaryButtonText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '800' },

  linkRow: { paddingVertical: spacing.md, alignItems: 'center' },
  linkText: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700' },
});
