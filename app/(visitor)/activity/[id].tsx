import { useLocalSearchParams, useRouter } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import { ActivityDetailSkeleton } from '@/components/activity-detail-skeleton';
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
    return <ActivityDetailSkeleton />;
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
