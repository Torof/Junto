import { useState, useMemo } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet, Alert } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { supabase } from '@/services/supabase';
import { useAuthStore } from '@/store/auth-store';
import { LogoSpinner } from '@/components/logo-spinner';
import { getFriendlyError } from '@/utils/friendly-error';

export default function OnboardingScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const [ageConfirmed, setAgeConfirmed] = useState(false);
  const [tosAccepted, setTosAccepted] = useState(false);
  const [isLoading, setIsLoading] = useState(false);

  const handleSubmit = async () => {
    if (!ageConfirmed || !tosAccepted) return;

    setIsLoading(true);
    try {
      const { error: ageError } = await supabase.rpc('confirm_age_adult');
      if (ageError) throw ageError;

      const { error: tosError } = await supabase.rpc('accept_tos');
      if (tosError) throw tosError;

      useAuthStore.getState().triggerRefresh();
      setTimeout(() => router.replace('/(auth)/(tabs)/carte'), 300);
    } catch (err) {
      Alert.alert(t('onboarding.error'), getFriendlyError(err, 'generic'));
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <View style={[styles.container, { paddingTop: insets.top, paddingBottom: insets.bottom }]}>
      <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false} keyboardShouldPersistTaps="handled">
        <Text style={styles.title}>{t('onboarding.welcome')}</Text>
        <Text style={styles.subtitle}>{t('onboarding.completeProfile')}</Text>

        <Pressable style={styles.checkbox} onPress={() => setAgeConfirmed(!ageConfirmed)}>
          <View style={[styles.checkboxBox, ageConfirmed && styles.checkboxChecked]}>
            {ageConfirmed && <Text style={styles.checkmark}>✓</Text>}
          </View>
          <Text style={styles.checkboxLabel}>{t('onboarding.confirmAdult')}</Text>
        </Pressable>

        <Pressable style={styles.checkbox} onPress={() => setTosAccepted(!tosAccepted)}>
          <View style={[styles.checkboxBox, tosAccepted && styles.checkboxChecked]}>
            {tosAccepted && <Text style={styles.checkmark}>✓</Text>}
          </View>
          <Text style={styles.checkboxLabel}>{t('onboarding.acceptTos')}</Text>
        </Pressable>

        <Pressable
          style={[styles.button, (!ageConfirmed || !tosAccepted || isLoading) && styles.buttonDisabled]}
          onPress={handleSubmit}
          disabled={!ageConfirmed || !tosAccepted || isLoading}
        >
          {isLoading ? (
            <LogoSpinner size={20} />
          ) : (
            <Text style={styles.buttonText}>{t('onboarding.continue')}</Text>
          )}
        </Pressable>
      </ScrollView>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  content: {
    flexGrow: 1,
    justifyContent: 'center',
    paddingHorizontal: spacing.xl,
  },
  title: {
    color: colors.textPrimary,
    fontSize: fontSizes.xl,
    fontWeight: 'bold',
    textAlign: 'center',
    marginBottom: spacing.xs,
  },
  subtitle: {
    color: colors.textSecondary,
    fontSize: fontSizes.md,
    textAlign: 'center',
    marginBottom: spacing.xl,
  },
  checkbox: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: spacing.xl,
  },
  checkboxBox: {
    width: 24,
    height: 24,
    borderRadius: radius.sm,
    borderWidth: 2,
    borderColor: colors.textSecondary,
    marginRight: spacing.sm,
    alignItems: 'center',
    justifyContent: 'center',
  },
  checkboxChecked: {
    backgroundColor: colors.cta,
    borderColor: colors.cta,
  },
  checkmark: {
    color: colors.textPrimary,
    fontSize: 14,
    fontWeight: 'bold',
  },
  checkboxLabel: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    flex: 1,
  },
  button: {
    backgroundColor: colors.cta,
    borderRadius: radius.md,
    paddingVertical: spacing.md,
    alignItems: 'center',
  },
  buttonDisabled: {
    opacity: 0.4,
  },
  buttonText: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    fontWeight: 'bold',
  },
});
