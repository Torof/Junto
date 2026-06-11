import type { QueryClient, QueryKey } from '@tanstack/react-query';

// Trailing-edge throttle for realtime-driven cache invalidation.
// postgres_changes fires once per row event on every connected client;
// invalidating immediately per event turns one busy minute into a
// refetch storm across the fleet (prod audit D, 2026-06-11). The first
// event in a window schedules a single invalidation; later events in
// the same window ride along.
export function makeDebouncedInvalidator(
  queryClient: QueryClient,
  queryKey: QueryKey,
  delayMs = 2000,
) {
  let timer: ReturnType<typeof setTimeout> | null = null;
  const fire = () => {
    if (timer) return;
    timer = setTimeout(() => {
      timer = null;
      queryClient.invalidateQueries({ queryKey });
    }, delayMs);
  };
  fire.cancel = () => {
    if (timer) {
      clearTimeout(timer);
      timer = null;
    }
  };
  return fire;
}
