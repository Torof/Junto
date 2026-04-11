import { View, ActivityIndicator, StyleSheet } from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { colors } from '@/constants/theme';
import { activityService } from '@/services/activity-service';
import { ActivityDetail } from '@/components/activity-detail';

export default function AuthActivityScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { t } = useTranslation();

  const { data: activity, isLoading } = useQuery({
    queryKey: ['activity', id],
    queryFn: () => activityService.getById(id ?? ''),
    enabled: !!id,
  });

  if (isLoading || !activity) {
    return (
      <View style={styles.loading}>
        <ActivityIndicator size="large" color={colors.cta} />
      </View>
    );
  }

  // Join mechanics in Sprint 4 — button visible but not functional yet
  return (
    <ActivityDetail
      activity={activity}
      onJoin={() => {}}
      joinLabel={t('activity.join')}
    />
  );
}

const styles = StyleSheet.create({
  loading: {
    flex: 1,
    backgroundColor: colors.background,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
