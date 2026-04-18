import { useState } from 'react';
import { View, Text, Pressable, StyleSheet, Alert, Platform } from 'react-native';
import DateTimePicker from '@react-native-community/datetimepicker';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { supabase } from '@/services/supabase';
import { useAuthStore } from '@/store/auth-store';
import { LogoSpinner } from '@/components/logo-spinner';
import { getFriendlyError } from '@/utils/friendly-error';

export default function OnboardingScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const [dateOfBirth, setDateOfBirth] = useState<Date | null>(null);
  const [showPicker, setShowPicker] = useState(false);
  const [tosAccepted, setTosAccepted] = useState(false);
  const [isLoading, setIsLoading] = useState(false);

  const maxDate = new Date();
  maxDate.setFullYear(maxDate.getFullYear() - 18);

  const handleDateChange = (_event: unknown, selectedDate?: Date) => {
    setShowPicker(Platform.OS === 'ios');
    if (selectedDate) {
      setDateOfBirth(selectedDate);
    }
  };

  const handleSubmit = async () => {
    if (!dateOfBirth || !tosAccepted) return;

    setIsLoading(true);
    try {
      const dobString = dateOfBirth.toISOString().split('T')[0] ?? '';

      const { error: dobError } = await supabase.rpc('set_date_of_birth', {
        p_date_of_birth: dobString,
      });
      if (dobError) throw dobError;

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

  const formatDate = (date: Date) => {
    return date.toLocaleDateString();
  };

  return (
    <View style={styles.container}>
      <View style={styles.content}>
        <Text style={styles.title}>{t('onboarding.welcome')}</Text>
        <Text style={styles.subtitle}>{t('onboarding.completeProfile')}</Text>

        <Text style={styles.label}>{t('onboarding.dateOfBirth')}</Text>
        <Pressable style={styles.dateButton} onPress={() => setShowPicker(true)}>
          <Text style={[styles.dateText, !dateOfBirth && styles.placeholder]}>
            {dateOfBirth ? formatDate(dateOfBirth) : t('onboarding.selectDate')}
          </Text>
        </Pressable>

        {showPicker && (
          <DateTimePicker
            value={dateOfBirth ?? maxDate}
            mode="date"
            maximumDate={maxDate}
            minimumDate={new Date(1920, 0, 1)}
            onChange={handleDateChange}
          />
        )}

        <Pressable style={styles.checkbox} onPress={() => setTosAccepted(!tosAccepted)}>
          <View style={[styles.checkboxBox, tosAccepted && styles.checkboxChecked]}>
            {tosAccepted && <Text style={styles.checkmark}>✓</Text>}
          </View>
          <Text style={styles.checkboxLabel}>{t('onboarding.acceptTos')}</Text>
        </Pressable>

        <Pressable
          style={[styles.button, (!dateOfBirth || !tosAccepted || isLoading) && styles.buttonDisabled]}
          onPress={handleSubmit}
          disabled={!dateOfBirth || !tosAccepted || isLoading}
        >
          {isLoading ? (
            <LogoSpinner size={20} />
          ) : (
            <Text style={styles.buttonText}>{t('onboarding.continue')}</Text>
          )}
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  content: {
    flex: 1,
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
  label: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    marginBottom: spacing.sm,
  },
  dateButton: {
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.md,
    marginBottom: spacing.lg,
  },
  dateText: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
  },
  placeholder: {
    color: colors.textSecondary,
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
