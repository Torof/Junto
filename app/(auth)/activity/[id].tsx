import { useEffect } from 'react';
import { View, ActivityIndicator, StyleSheet } from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { colors } from '@/constants/theme';
import { activityService } from '@/services/activity-service';
import { participationService } from '@/services/participation-service';
import { ActivityDetail } from '@/components/activity-detail';
import { supabase } from '@/services/supabase';

export default function AuthActivityScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const queryClient = useQueryClient();

  // Lazy transition — check if this activity needs a status update
  useEffect(() => {
    if (!id) return;
    supabase.rpc('transition_single_activity' as 'join_activity', {
      p_activity_id: id,
    } as unknown as { p_activity_id: string }).then((result) => {
      if (result.data) {
        // Refetch activity if status changed
        queryClient.invalidateQueries({ queryKey: ['activity', id] });
      }
    });
  }, [id, queryClient]);

  const { data: activity, isLoading: activityLoading } = useQuery({
    queryKey: ['activity', id],
    queryFn: () => activityService.getById(id ?? ''),
    enabled: !!id,
  });

  const { data: participation, isLoading: participationLoading } = useQuery({
    queryKey: ['participation', id],
    queryFn: () => participationService.getMyStatus(id ?? ''),
    enabled: !!id,
    staleTime: 0,
  });

  const { data: user } = useQuery({
    queryKey: ['currentUser'],
    queryFn: async () => (await supabase.auth.getUser()).data.user,
  });

  if (activityLoading || participationLoading || !activity) {
    return (
      <View style={styles.loading}>
        <ActivityIndicator size="large" color={colors.cta} />
      </View>
    );
  }

  return (
    <ActivityDetail
      activity={activity}
      participation={participation ?? null}
      isCreator={user?.id === activity.creator_id}
      isAuthenticated={true}
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
