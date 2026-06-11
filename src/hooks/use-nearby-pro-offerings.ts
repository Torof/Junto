import { useEffect, useMemo } from 'react';
import { useQuery, useQueryClient, keepPreviousData } from '@tanstack/react-query';
import { proOfferingService } from '@/services/pro-offering-service';
import { supabase } from '@/services/supabase';
import { makeDebouncedInvalidator } from '@/utils/debounced-invalidate';
import type { MapBounds } from './use-nearby-activities';

// Sibling of useNearbyActivities + useNearbyPros — fetches pro offering
// card pins for the current viewport. Realtime refreshes the nearby
// cache (scoped + throttled, see debounced-invalidate) so newly
// published catalog items appear without a manual refresh.
export function useNearbyProOfferings(bounds?: MapBounds | null) {
  const queryClient = useQueryClient();

  const invalidateNearby = useMemo(
    () => makeDebouncedInvalidator(queryClient, ['pro-offerings', 'nearby']),
    [queryClient],
  );

  useEffect(() => {
    const channel = supabase
      .channel('pro-offerings-nearby')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'pro_offerings' },
        invalidateNearby,
      )
      .subscribe();
    return () => {
      invalidateNearby.cancel();
      supabase.removeChannel(channel);
    };
  }, [invalidateNearby]);

  return useQuery({
    queryKey: ['pro-offerings', 'nearby', bounds],
    queryFn: () => proOfferingService.getNearby(bounds ?? undefined),
    enabled: !!bounds,
    placeholderData: keepPreviousData,
  });
}
