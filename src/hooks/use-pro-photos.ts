import { useQuery } from '@tanstack/react-query';
import { proPhotoService, proOfferingPhotoService } from '@/services/pro-photo-service';

// Pro page gallery — keyed on pro_id so the same query feeds both the
// pro page Photos tab and the owner's PhotoManager. Stale-while-revalidate
// is fine here; new uploads invalidate explicitly.
export function useProPhotos(proId: string | null | undefined) {
  return useQuery({
    queryKey: ['pro-photos', proId],
    queryFn: () => proPhotoService.listByPro(proId!),
    enabled: !!proId,
  });
}

export function useProOfferingPhotos(offeringId: string | null | undefined) {
  return useQuery({
    queryKey: ['pro-offering-photos', offeringId],
    queryFn: () => proOfferingPhotoService.listByOffering(offeringId!),
    enabled: !!offeringId,
  });
}
