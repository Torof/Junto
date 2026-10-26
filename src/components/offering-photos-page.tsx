import { useMemo } from 'react';
import { View, Pressable, ScrollView, StyleSheet, Alert } from 'react-native';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { Camera, Plus } from 'lucide-react-native';
import { AppText } from '@/components/app-text';
import { PhotoGallery } from '@/components/photo-gallery';
import { useColors } from '@/hooks/use-theme';
import { useProOfferingPhotos } from '@/hooks/use-pro-photos';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import type { ProOffering } from '@/services/pro-offering-service';
import { proCommunityPhotoService } from '@/services/pro-photo-service';
import {
  pickAndUploadProOfferingPhotos, removeProOfferingPhoto, pickAndUploadCommunityPhotos, removeProCommunityPhoto,
} from '@/utils/pro-photo-upload';
import { getFriendlyError } from '@/utils/friendly-error';

const GALLERY_MAX = 25;

interface Props {
  offering: ProOffering;
  isOwner: boolean;
  currentUserId: string | null;
}

// All the photos of a pro outing as a plain page (Scott 2026-10-26: « Voir
// tout » on the outing sheet must open the photos, not the old page). One
// merged grid — the pro's curated photos then the community ones, in the
// same order as the sheet's four thumbnails — tap opens the lightbox. The
// chip adds to the curated gallery for the owner, to the community photos
// for everyone else; delete shows on the tiles the viewer may moderate
// (owner: every tile · visitor: own contributions), as on the pro page.
export function OfferingPhotosPage({ offering, isOwner, currentUserId }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const queryClient = useQueryClient();

  const { data: photos = [] } = useProOfferingPhotos(offering.id);
  const { data: communityPhotos = [] } = useQuery({
    queryKey: ['offering-community-photos', offering.id],
    queryFn: () => proCommunityPhotoService.listByOffering(offering.id),
  });

  const allPhotos = [
    ...photos.map((p) => ({ id: p.id, photo_url: p.photo_url, kind: 'curated' as const, contributor_id: null as string | null })),
    ...communityPhotos.map((c) => ({ id: c.id, photo_url: c.photo_url, kind: 'community' as const, contributor_id: c.contributor_id as string | null })),
  ];
  const byId = new Map(allPhotos.map((p) => [p.id, p]));

  const invalidatePhotos = async () => {
    await queryClient.invalidateQueries({ queryKey: ['pro-offering-photos', offering.id] });
    await queryClient.invalidateQueries({ queryKey: ['offering-community-photos', offering.id] });
  };
  const run = async (action: () => Promise<unknown>) => {
    try {
      await action();
      await invalidatePhotos();
    } catch (err) {
      Alert.alert(t('auth.error', { defaultValue: 'Erreur' }), getFriendlyError(err, 'generic'));
    }
  };
  // The 5-per-user-per-pro cap (profile + offerings combined) is enforced
  // server-side with the friendly junto.photo_limit message — the picker
  // just caps one batch.
  const handleAdd = () => run(() => isOwner
    ? pickAndUploadProOfferingPhotos(offering.id, GALLERY_MAX - photos.length)
    : pickAndUploadCommunityPhotos(offering.pro_id, 5, null, offering.id));
  const canDelete = (id: string) => {
    const p = byId.get(id);
    if (!p) return false;
    return p.kind === 'curated' ? isOwner : isOwner || p.contributor_id === currentUserId;
  };
  const handleDelete = (id: string) => {
    const p = byId.get(id);
    if (!p) return;
    void run(() => (p.kind === 'curated' ? removeProOfferingPhoto(p.id) : removeProCommunityPhoto(p.id)));
  };
  const canAdd = !isOwner || photos.length < GALLERY_MAX;

  return (
    <ScrollView style={styles.page} contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
      {canAdd ? (
        <Pressable style={styles.addPhotoChip} onPress={handleAdd}>
          <View style={styles.addPhotoIconRow}>
            <Camera size={16} color={colors.cta} strokeWidth={2.4} />
            <Plus size={12} color={colors.cta} strokeWidth={3} />
          </View>
          <AppText style={styles.addPhotoChipText}>{t('pro.addPhotos', { defaultValue: 'Ajouter des photos' })}</AppText>
        </Pressable>
      ) : null}
      <PhotoGallery
        photos={allPhotos}
        emptyText={t('pro.picturesEmpty', { defaultValue: 'Aucune photo pour le moment.' })}
        canDelete={(p) => canDelete(p.id)}
        onDelete={(p) => handleDelete(p.id)}
      />
    </ScrollView>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  page: { flex: 1, backgroundColor: colors.background },
  content: { paddingTop: spacing.md, paddingBottom: spacing.xl + 24 },
  addPhotoChip: {
    flexDirection: 'row',
    alignItems: 'center',
    alignSelf: 'center',
    gap: spacing.xs,
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.md,
    borderRadius: radius.full,
    borderWidth: 1.5,
    borderColor: colors.cta,
    marginBottom: spacing.md,
  },
  addPhotoIconRow: { flexDirection: 'row', alignItems: 'center', gap: 1 },
  addPhotoChipText: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700' },
});
