import * as ImagePicker from 'expo-image-picker';
import * as ImageManipulator from 'expo-image-manipulator';
import { readAsStringAsync, EncodingType } from 'expo-file-system/legacy';
import { decode } from 'base64-arraybuffer';
import { supabase } from '@/services/supabase';
import { proPhotoService, proOfferingPhotoService, proCommunityPhotoService } from '@/services/pro-photo-service';

// Gallery photos are free-aspect (no crop) since users curate their own
// composition. Wider ceiling than the 3:1 banner so portrait shots from
// the photo library don't get a brutal downscale.
const MAX_WIDTH = 1600;
const ALLOWED_TYPES = ['image/jpeg', 'image/png', 'image/webp'];

interface UploadOutcome {
  photoId: string;
  photoUrl: string;
}

// Internal: pick → resize → magic-byte check → upload one asset to the
// `pro-photos` bucket under `pathPrefix`. Returns the public URL only;
// the metadata insert is done by the caller via the appropriate add RPC.
async function uploadAsset(
  asset: ImagePicker.ImagePickerAsset,
  pathPrefix: string,
  uniqueSuffix: string,
): Promise<string> {
  if (asset.mimeType && !ALLOWED_TYPES.includes(asset.mimeType)) {
    throw new Error('Invalid image type');
  }

  const manipulated = await ImageManipulator.manipulateAsync(
    asset.uri,
    [{ resize: { width: MAX_WIDTH } }],
    { compress: 0.85, format: ImageManipulator.SaveFormat.JPEG },
  );

  const base64 = await readAsStringAsync(manipulated.uri, {
    encoding: EncodingType.Base64,
  });

  if (!base64.startsWith('/9j/')) {
    throw new Error('Invalid image type');
  }

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('Not authenticated');

  const objectName = `${user.id}/${pathPrefix}/${uniqueSuffix}.jpg`;

  const { error: uploadError } = await supabase.storage
    .from('pro-photos')
    .upload(objectName, decode(base64), {
      contentType: 'image/jpeg',
      upsert: true,
    });
  if (uploadError) throw uploadError;

  const { data: { publicUrl } } = supabase.storage
    .from('pro-photos')
    .getPublicUrl(objectName);

  // Cache-bust suffix so successive uploads under the same name (rare
  // here since timestamp is in the path) don't show a stale CDN copy.
  return `${publicUrl}?t=${Date.now()}`;
}

// Multi-pick + sequential upload for the pro page gallery. Caps at
// `remainingSlots` so the add RPC's 25-cap doesn't reject mid-batch.
// Returns one outcome per successful add — failures (cap, invalid
// mime, network) throw and abort the batch.
export async function pickAndUploadProPhotos(
  remainingSlots: number,
): Promise<UploadOutcome[]> {
  if (remainingSlots <= 0) return [];

  const result = await ImagePicker.launchImageLibraryAsync({
    mediaTypes: ['images'],
    allowsMultipleSelection: true,
    selectionLimit: remainingSlots,
    quality: 0.85,
  });

  if (result.canceled || result.assets.length === 0) return [];

  const outcomes: UploadOutcome[] = [];
  for (let i = 0; i < result.assets.length; i++) {
    const asset = result.assets[i]!;
    const suffix = `${Date.now()}-${i}`;
    const photoUrl = await uploadAsset(asset, 'gallery', suffix);
    const photoId = await proPhotoService.add(photoUrl);
    outcomes.push({ photoId, photoUrl });
  }
  return outcomes;
}

export async function pickAndUploadProOfferingPhotos(
  offeringId: string,
  remainingSlots: number,
): Promise<UploadOutcome[]> {
  if (remainingSlots <= 0) return [];

  const result = await ImagePicker.launchImageLibraryAsync({
    mediaTypes: ['images'],
    allowsMultipleSelection: true,
    selectionLimit: remainingSlots,
    quality: 0.85,
  });

  if (result.canceled || result.assets.length === 0) return [];

  const outcomes: UploadOutcome[] = [];
  for (let i = 0; i < result.assets.length; i++) {
    const asset = result.assets[i]!;
    const suffix = `${Date.now()}-${i}`;
    const photoUrl = await uploadAsset(asset, `offering/${offeringId}/gallery`, suffix);
    const photoId = await proOfferingPhotoService.add(offeringId, photoUrl);
    outcomes.push({ photoId, photoUrl });
  }
  return outcomes;
}

// Community photos — anyone can add (max 5 per user per pro). Uploaded under
// the contributor's own `<uid>/community/<proId>/…` path so the storage
// insert_own policy allows it; optionally linked to a review via reviewId.
export async function pickAndUploadCommunityPhotos(
  proId: string,
  remainingSlots: number,
  reviewId?: string | null,
  offeringId?: string | null,
): Promise<UploadOutcome[]> {
  if (remainingSlots <= 0) return [];

  const result = await ImagePicker.launchImageLibraryAsync({
    mediaTypes: ['images'],
    allowsMultipleSelection: true,
    selectionLimit: remainingSlots,
    quality: 0.85,
  });

  if (result.canceled || result.assets.length === 0) return [];

  const outcomes: UploadOutcome[] = [];
  for (let i = 0; i < result.assets.length; i++) {
    const asset = result.assets[i]!;
    const suffix = `${Date.now()}-${i}`;
    const photoUrl = await uploadAsset(asset, `community/${proId}`, suffix);
    const photoId = await proCommunityPhotoService.add(proId, photoUrl, reviewId ?? null, offeringId ?? null);
    outcomes.push({ photoId, photoUrl });
  }
  return outcomes;
}

// Pick + upload to storage only (no DB insert) — returns the public URLs.
// The review composer uses this so photos can be previewed before the review
// exists, then linked to it (via add_pro_community_photo) on submit.
export async function pickAndUploadRawPhotos(
  proId: string,
  remainingSlots: number,
): Promise<string[]> {
  if (remainingSlots <= 0) return [];

  const result = await ImagePicker.launchImageLibraryAsync({
    mediaTypes: ['images'],
    allowsMultipleSelection: true,
    selectionLimit: remainingSlots,
    quality: 0.85,
  });

  if (result.canceled || result.assets.length === 0) return [];

  const urls: string[] = [];
  for (let i = 0; i < result.assets.length; i++) {
    const asset = result.assets[i]!;
    urls.push(await uploadAsset(asset, `community/${proId}`, `${Date.now()}-${i}`));
  }
  return urls;
}

// Remove RPCs are wrapped here too so callers don't reach across files
// for a single related action — keeps the gallery API surface one import.
export async function removeProPhoto(photoId: string): Promise<void> {
  await proPhotoService.remove(photoId);
}

export async function removeProCommunityPhoto(photoId: string): Promise<void> {
  await proCommunityPhotoService.remove(photoId);
}

export async function removeProOfferingPhoto(photoId: string): Promise<void> {
  await proOfferingPhotoService.remove(photoId);
}
