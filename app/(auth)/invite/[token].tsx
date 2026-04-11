import { useEffect } from 'react';
import { View, Text, ActivityIndicator, StyleSheet } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { colors, fontSizes, spacing } from '@/constants/theme';
import { activityService } from '@/services/activity-service';

export default function InviteScreen() {
  const { token } = useLocalSearchParams<{ token: string }>();
  const router = useRouter();
  const { t } = useTranslation();

  const { data: activity, isLoading, error } = useQuery({
    queryKey: ['invite', token],
    queryFn: () => activityService.getByInviteToken(token ?? ''),
    enabled: !!token,
  });

  useEffect(() => {
    if (activity) {
      router.replace(`/(auth)/activity/${activity.id}`);
    }
  }, [activity, router]);

  if (isLoading) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color={colors.cta} />
      </View>
    );
  }

  if (error || !activity) {
    return (
      <View style={styles.center}>
        <Text style={styles.errorText}>{t('invite.invalid')}</Text>
      </View>
    );
  }

  return null;
}

const styles = StyleSheet.create({
  center: {
    flex: 1,
    backgroundColor: colors.background,
    alignItems: 'center',
    justifyContent: 'center',
  },
  errorText: {
    color: colors.textSecondary,
    fontSize: fontSizes.md,
  },
});
