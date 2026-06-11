import { useEffect, useMemo } from 'react';
import { useQuery, useQueryClient, keepPreviousData } from '@tanstack/react-query';
import { proService } from '@/services/pro-service';
import { supabase } from '@/services/supabase';
import { makeDebouncedInvalidator } from '@/utils/debounced-invalidate';
import type { MapBounds } from './use-nearby-activities';

// Sibling of useNearbyActivities — fetches pro pins for the current
// viewport. Same scoped + throttled realtime refresh and
// keep-previous-data pattern.
export function useNearbyPros(bounds?: MapBounds | null) {
  const queryClient = useQueryClient();

  const invalidateNearby = useMemo(
    () => makeDebouncedInvalidator(queryClient, ['pros', 'nearby']),
    [queryClient],
  );

  useEffect(() => {
    const channel = supabase
      .channel('pros-nearby')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'pro_profiles' },
        invalidateNearby,
      )
      .subscribe();
    return () => {
      invalidateNearby.cancel();
      supabase.removeChannel(channel);
    };
  }, [invalidateNearby]);

  return useQuery({
    queryKey: ['pros', 'nearby', bounds],
    queryFn: () => proService.getNearby(bounds ?? undefined),
    enabled: !!bounds,
    placeholderData: keepPreviousData,
  });
}
