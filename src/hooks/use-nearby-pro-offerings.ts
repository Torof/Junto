import { useEffect } from 'react';
import { useQuery, useQueryClient, keepPreviousData } from '@tanstack/react-query';
import { proOfferingService } from '@/services/pro-offering-service';
import { supabase } from '@/services/supabase';
import type { MapBounds } from './use-nearby-activities';

// Sibling of useNearbyActivities + useNearbyPros — fetches pro offering
// lozenge pins for the current viewport. Realtime invalidates on any
// pro_offerings change so newly published catalog items appear without
// a manual refresh.
export function useNearbyProOfferings(bounds?: MapBounds | null) {
  const queryClient = useQueryClient();

  useEffect(() => {
    const channel = supabase
      .channel('pro-offerings-nearby')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'pro_offerings' },
        () => {
          queryClient.invalidateQueries({ queryKey: ['pro-offerings'] });
        },
      )
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
  }, [queryClient]);

  return useQuery({
    queryKey: ['pro-offerings', 'nearby', bounds],
    queryFn: () => proOfferingService.getNearby(bounds ?? undefined),
    enabled: !!bounds,
    placeholderData: keepPreviousData,
  });
}
