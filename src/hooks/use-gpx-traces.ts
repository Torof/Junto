import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { gpxTraceService } from '@/services/gpx-trace-service';
import type { GeoJsonLineString } from '@/services/activity-service';

const GPX_TRACES_KEY = ['gpx-traces'];

export function useGpxTraces() {
  return useQuery({
    queryKey: GPX_TRACES_KEY,
    queryFn: gpxTraceService.list,
  });
}

export function useCreateGpxTrace() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ name, geojson }: { name: string; geojson: GeoJsonLineString }) =>
      gpxTraceService.create(name, geojson),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: GPX_TRACES_KEY }),
  });
}

export function useRenameGpxTrace() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ id, name }: { id: string; name: string }) => gpxTraceService.rename(id, name),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: GPX_TRACES_KEY }),
  });
}

export function useDeleteGpxTrace() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => gpxTraceService.remove(id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: GPX_TRACES_KEY }),
  });
}
