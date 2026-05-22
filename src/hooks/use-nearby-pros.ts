import { useEffect } from 'react';
import { useQuery, useQueryClient, keepPreviousData } from '@tanstack/react-query';
import { proService } from '@/services/pro-service';
import { supabase } from '@/services/supabase';
import type { MapBounds } from './use-nearby-activities';

// Sibling of useNearbyActivities — fetches pro pins for the current
// viewport. Same realtime + keep-previous-data pattern. Pre-launch
// scale, no per-user filter; geo bbox is the only scoping primitive.
export function useNearbyPros(bounds?: MapBounds | null) {
  const queryClient = useQueryClient();

  useEffect(() => {
    const channel = supabase
      .channel('pros-nearby')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'pro_profiles' },
        () => {
          queryClient.invalidateQueries({ queryKey: ['pros'] });
        },
      )
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
  }, [queryClient]);

  return useQuery({
    queryKey: ['pros', 'nearby', bounds],
    queryFn: () => proService.getNearby(bounds ?? undefined),
    enabled: !!bounds,
    placeholderData: keepPreviousData,
  });
}
