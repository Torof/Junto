import { useEffect, useMemo } from 'react';
import { useQuery, useQueryClient, keepPreviousData } from '@tanstack/react-query';
import { activityService } from '@/services/activity-service';
import { supabase } from '@/services/supabase';
import { makeDebouncedInvalidator } from '@/utils/debounced-invalidate';

export interface MapBounds {
  swLng: number;
  swLat: number;
  neLng: number;
  neLat: number;
}

export function useNearbyActivities(bounds?: MapBounds | null) {
  const queryClient = useQueryClient();

  // Realtime: refresh the map's nearby caches on activity create/edit/
  // delete. Scoped to ['activities','nearby'] (the broad ['activities']
  // prefix dragged every list/detail query into each event) and
  // throttled — one invalidation per 2s window per client, not one per
  // row event (prod audit D). Migration 00186 ensures activities is in
  // the publication.
  const invalidateNearby = useMemo(
    () => makeDebouncedInvalidator(queryClient, ['activities', 'nearby']),
    [queryClient],
  );

  useEffect(() => {
    const channel = supabase
      .channel('activities-nearby')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'activities' },
        invalidateNearby,
      )
      // A removal/acceptance touches participations, not activities — but
      // the map's private-outing visibility (view 00315) depends on the
      // caller's accepted participation, so a removed member's pin would
      // otherwise linger until they pan (Scott's audit, 2026-07-10).
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'participations' },
        invalidateNearby,
      )
      .subscribe();
    return () => {
      invalidateNearby.cancel();
      supabase.removeChannel(channel);
    };
  }, [invalidateNearby]);

  return useQuery({
    queryKey: ['activities', 'nearby', bounds],
    queryFn: () => activityService.getNearby(bounds ?? undefined),
    enabled: !!bounds,
    // Keep the previous result visible while a new viewport fetch is in flight,
    // otherwise pins blink off every time the user pans or zooms.
    placeholderData: keepPreviousData,
  });
}
