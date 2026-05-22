import * as ImagePicker from 'expo-image-picker';
import * as ImageManipulator from 'expo-image-manipulator';
import { readAsStringAsync, EncodingType } from 'expo-file-system/legacy';
import { decode } from 'base64-arraybuffer';
import { supabase } from '@/services/supabase';
import { proOfferingService } from '@/services/pro-offering-service';

// Offering banner — same magazine-cover treatment as the pro banner
// (3:1 crop) but scoped per-offering so different catalog items can
// each have a distinct hero.
const MAX_WIDTH = 1280;
const ALLOWED_TYPES = ['image/jpeg', 'image/png', 'image/webp'];

export async function pickAndUploadProOfferingImage(
  offeringId: string,
): Promise<string | null> {
  const result = await ImagePicker.launchImageLibraryAsync({
    mediaTypes: ['images'],
    allowsEditing: true,
    aspect: [3, 1],
    quality: 0.85,
  });

  if (result.canceled || !result.assets[0]) return null;

  const asset = result.assets[0];

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

  const objectName = `${user.id}/offering/${offeringId}/${Date.now()}.jpg`;

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

  const imageUrl = `${publicUrl}?t=${Date.now()}`;
  await proOfferingService.setImage(offeringId, imageUrl);

  return imageUrl;
}

export async function removeProOfferingImage(offeringId: string): Promise<void> {
  await proOfferingService.setImage(offeringId, null);
}
