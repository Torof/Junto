import { useEffect } from 'react';
import { useQuery, useQueryClient, keepPreviousData } from '@tanstack/react-query';
import { activityService } from '@/services/activity-service';
import { supabase } from '@/services/supabase';

export interface MapBounds {
  swLng: number;
  swLat: number;
  neLng: number;
  neLat: number;
}

export function useNearbyActivities(bounds?: MapBounds | null) {
  const queryClient = useQueryClient();

  // Realtime: invalidate every ['activities', ...] cache (TanStack matches
  // by prefix) on any activity create/edit/delete. The map / list re-fetches
  // for the current bounds so new activities appear without manual pan.
  // Migration 00180 added activities to the publication. No per-user filter
  // — pre-launch traffic is low; geographic scoping comes later if needed.
  useEffect(() => {
    const channel = supabase
      .channel('activities-nearby')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'activities' },
        () => {
          queryClient.invalidateQueries({ queryKey: ['activities'] });
        },
      )
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
  }, [queryClient]);

  return useQuery({
    queryKey: ['activities', 'nearby', bounds],
    queryFn: () => activityService.getNearby(bounds ?? undefined),
    enabled: !!bounds,
    // Keep the previous result visible while a new viewport fetch is in flight,
    // otherwise pins blink off every time the user pans or zooms.
    placeholderData: keepPreviousData,
  });
}
