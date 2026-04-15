import { useState } from 'react';
import { View, Text, TextInput, Pressable, ScrollView, StyleSheet, Alert, Image } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { authService } from '@/services/auth-service';

export default function LoginScreen() {
  const { t } = useTranslation();
  const insets = useSafeAreaInsets();
  const [isRegister, setIsRegister] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [isLoading, setIsLoading] = useState(false);

  const friendlyAuthError = (raw: string): string => {
    const m = raw.toLowerCase();
    if (m.includes('invalid login credentials')) return t('auth.errInvalidCredentials');
    if (m.includes('email not confirmed')) return t('auth.errEmailNotConfirmed');
    if (m.includes('user already registered') || m.includes('already been registered')) return t('auth.errEmailTaken');
    if (m.includes('password should be at least')) return t('auth.errPasswordTooShort');
    if (m.includes('unable to validate email') || m.includes('invalid email')) return t('auth.errInvalidEmail');
    if (m.includes('rate limit') || m.includes('too many requests')) return t('auth.errRateLimit');
    if (m.includes('network')) return t('auth.errNetwork');
    return raw;
  };

  const handleSubmit = async () => {
    if (!email.trim() || !password.trim()) return;
    setIsLoading(true);
    try {
      if (isRegister) {
        await authService.signUpWithEmail(email.trim(), password);
        Alert.alert(t('auth.checkEmail'), t('auth.confirmationSent'));
      } else {
        await authService.signInWithEmail(email.trim(), password);
      }
    } catch (err) {
      const raw = err instanceof Error ? err.message : t('auth.unknownError');
      Alert.alert(t('auth.error'), friendlyAuthError(raw));
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <ScrollView
      style={styles.container}
      contentContainerStyle={[styles.content, { paddingTop: insets.top + spacing.xl, paddingBottom: insets.bottom + spacing.xl }]}
      keyboardShouldPersistTaps="handled"
    >
      <Image source={require('../../assets/Junto_logo.png')} style={styles.logo} />
      <Text style={styles.title}>{t('app.name')}</Text>
      <Text style={styles.subtitle}>{isRegister ? t('auth.createAccount') : t('auth.signIn')}</Text>

      <TextInput
        style={styles.input}
        placeholder={t('auth.email')}
        placeholderTextColor={colors.textSecondary}
        value={email}
        onChangeText={setEmail}
        keyboardType="email-address"
        autoCapitalize="none"
        autoComplete="email"
      />

      <TextInput
        style={styles.input}
        placeholder={t('auth.password')}
        placeholderTextColor={colors.textSecondary}
        value={password}
        onChangeText={setPassword}
        secureTextEntry
        autoComplete={isRegister ? 'new-password' : 'current-password'}
      />

      <Pressable
        style={[styles.button, isLoading && styles.buttonDisabled]}
        onPress={handleSubmit}
        disabled={isLoading}
      >
        <Text style={styles.buttonText}>
          {isLoading ? '...' : isRegister ? t('auth.register') : t('auth.login')}
        </Text>
      </Pressable>

      <Pressable onPress={() => setIsRegister(!isRegister)}>
        <Text style={styles.toggleText}>
          {isRegister ? t('auth.hasAccount') : t('auth.noAccount')}
        </Text>
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
    flexGrow: 1,
    justifyContent: 'center',
    paddingHorizontal: spacing.xl,
  },
  logo: {
    width: 80,
    height: 80,
    alignSelf: 'center',
    marginBottom: spacing.md,
  },
  title: {
    color: colors.textPrimary,
    fontSize: fontSizes.xxl,
    fontWeight: 'bold',
    textAlign: 'center',
    marginBottom: spacing.xs,
  },
  subtitle: {
    color: colors.textSecondary,
    fontSize: fontSizes.lg,
    textAlign: 'center',
    marginBottom: spacing.xl,
  },
  input: {
    backgroundColor: colors.surface,
    color: colors.textPrimary,
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.md,
    fontSize: fontSizes.md,
    marginBottom: spacing.md,
  },
  button: {
    backgroundColor: colors.cta,
    borderRadius: radius.md,
    paddingVertical: spacing.md,
    alignItems: 'center',
    marginTop: spacing.sm,
  },
  buttonDisabled: {
    opacity: 0.6,
  },
  buttonText: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    fontWeight: 'bold',
  },
  toggleText: {
    color: colors.cta,
    fontSize: fontSizes.sm,
    textAlign: 'center',
    marginTop: spacing.lg,
  },
});
