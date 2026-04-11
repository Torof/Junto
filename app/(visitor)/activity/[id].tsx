import { View, ActivityIndicator, StyleSheet } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import { colors } from '@/constants/theme';
import { activityService } from '@/services/activity-service';
import { ActivityDetail } from '@/components/activity-detail';

export default function VisitorActivityScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();

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

  return (
    <ActivityDetail
      activity={activity}
      participation={null}
      isCreator={false}
      isAuthenticated={false}
      onJoinRedirect={() => router.push('/(visitor)/login')}
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
