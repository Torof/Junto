import { useCallback } from 'react';
import { useQuery } from '@tanstack/react-query';
import { participationService } from '@/services/participation-service';

// « Your » outings on the map (Scott 2026-11-03): the ones you organise, joined
// or asked to join. Under the ['activities'] key, so join / leave / cancel
// (which invalidate it) refresh the marks too.
export type ActivityMark = 'mine' | 'joined' | 'pending';

export function useMyActivityMarks() {
  const { data } = useQuery({
    queryKey: ['activities', 'my-marks'],
    queryFn: participationService.getMyMarks,
  });
  return useCallback(
    (a: { id: string; creator_id: string }): ActivityMark | null => {
      if (!data?.userId) return null;
      if (a.creator_id === data.userId) return 'mine';
      const st = data.statuses.get(a.id);
      return st === 'accepted' ? 'joined' : st === 'pending' ? 'pending' : null;
    },
    [data],
  );
}
