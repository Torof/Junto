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

  const invalidateNearby = useMemo(
    () => makeDebouncedInvalidator(queryClient, ['activities', 'nearby']),
    [queryClient],
  );

  useEffect(() => {
    // 00479 (audit AB-2): the map no longer listens to postgres_changes on
    // activities / participations (every open map received every write on
    // every outing). The server sends a content-less ping on the private
    // `map` topic — at most once per outing every 15 s, only for map-visible
    // changes on public/approval outings — and we refetch the viewport,
    // debounced. Signed-in users only (the topic is private); visitors refresh
    // on pan / focus.
    let channel: ReturnType<typeof supabase.channel> | null = null;
    let cancelled = false;
    void supabase.auth.getSession().then(({ data }) => {
      if (cancelled || !data.session) return;
      channel = supabase
        .channel('map', { config: { private: true } })
        .on('broadcast', { event: 'map' }, invalidateNearby)
        .subscribe();
    });
    return () => {
      cancelled = true;
      invalidateNearby.cancel();
      if (channel) supabase.removeChannel(channel);
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
