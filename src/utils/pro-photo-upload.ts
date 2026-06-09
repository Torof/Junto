import * as ImagePicker from 'expo-image-picker';
import * as ImageManipulator from 'expo-image-manipulator';
import { readAsStringAsync, EncodingType } from 'expo-file-system/legacy';
import { decode } from 'base64-arraybuffer';
import { supabase } from '@/services/supabase';
import { proPhotoService, proOfferingPhotoService } from '@/services/pro-photo-service';

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

// Remove RPCs are wrapped here too so callers don't reach across files
// for a single related action — keeps the gallery API surface one import.
export async function removeProPhoto(photoId: string): Promise<void> {
  await proPhotoService.remove(photoId);
}

export async function removeProOfferingPhoto(photoId: string): Promise<void> {
  await proOfferingPhotoService.remove(photoId);
}
