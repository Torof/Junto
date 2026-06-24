import { useEffect } from 'react';

import { Redirect, useLocalSearchParams } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { ActivityDetailSkeleton } from '@/components/activity-detail-skeleton';
import { activityService } from '@/services/activity-service';
import { participationService } from '@/services/participation-service';
import { ActivityDetail } from '@/components/activity-detail';
import { ActivityUnavailable } from '@/components/activity-unavailable';
import { supabase } from '@/services/supabase';
import { useAuth } from '@/hooks/use-auth';

export default function AuthActivityScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const queryClient = useQueryClient();
  const { isAuthenticated, isLoading: authLoading, isSuspended } = useAuth();

  // Lazy transition — check if this activity needs a status update.
  // Must be declared before any early return per Rules of Hooks.
  useEffect(() => {
    if (!id) return;
    supabase.rpc('transition_single_activity' as 'join_activity', {
      p_activity_id: id,
    } as unknown as { p_activity_id: string }).then((result) => {
      if (result.data) {
        queryClient.invalidateQueries({ queryKey: ['activity', id] });
      }
    });
  }, [id, queryClient]);

  const { data: activity, isLoading: activityLoading } = useQuery({
    queryKey: ['activity', id],
    queryFn: () => activityService.getById(id ?? ''),
    enabled: !!id && isAuthenticated,
  });

  const { data: participation, isLoading: participationLoading } = useQuery({
    queryKey: ['participation', id],
    queryFn: () => participationService.getMyStatus(id ?? ''),
    enabled: !!id && isAuthenticated,
    staleTime: 0,
  });

  const { data: user, isLoading: userLoading } = useQuery({
    queryKey: ['currentUser-auth'],
    queryFn: async () => (await supabase.auth.getUser()).data.user,
    enabled: isAuthenticated,
  });

  // Per-screen auth gate. AuthGate at the root handles routing, but a
  // cold deep-link (`juntoapp://activity/abc`) can briefly mount this
  // screen before AuthGate's redirect lands. Short-circuit here so
  // unauthenticated or suspended users never see content. AUDIT_SECURITY_2 C2.
  // (All hooks above must execute regardless — React Rules of Hooks.)
  if (authLoading) {
    return <ActivityDetailSkeleton />;
  }
  if (!isAuthenticated) {
    return <Redirect href="/(visitor)/login" />;
  }
  if (isSuspended) {
    return <Redirect href="/(visitor)/suspended" />;
  }

  // Activity still resolving → skeleton. Resolved to nothing (finished,
  // deleted, or no longer accessible — e.g. a notification to an outing that
  // has ended) → graceful "unavailable" rather than an endless skeleton.
  if (activityLoading) {
    return <ActivityDetailSkeleton />;
  }
  if (!activity) {
    return <ActivityUnavailable fallbackHref="/(auth)/(tabs)/carte" />;
  }
  if (participationLoading || userLoading) {
    return <ActivityDetailSkeleton />;
  }

  return (
    <ActivityDetail
      activity={activity}
      participation={participation ?? null}
      isCreator={user?.id === activity.creator_id}
      isAuthenticated={isAuthenticated}
    />
  );
}
