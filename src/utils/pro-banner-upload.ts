import * as ImagePicker from 'expo-image-picker';
import * as ImageManipulator from 'expo-image-manipulator';
import { readAsStringAsync, EncodingType } from 'expo-file-system/legacy';
import { decode } from 'base64-arraybuffer';
import { supabase } from '@/services/supabase';
import { proService } from '@/services/pro-service';

// Bigger than the avatar — banners are the magazine-cover for the
// pro page so we need width.
const MAX_WIDTH = 1280;
const ALLOWED_TYPES = ['image/jpeg', 'image/png', 'image/webp'];

export async function pickAndUploadProBanner(): Promise<string | null> {
  const result = await ImagePicker.launchImageLibraryAsync({
    mediaTypes: ['images'],
    // 3:1 magazine-cover crop. Locks the aspect so the layout below
    // is predictable across pros.
    allowsEditing: true,
    aspect: [3, 1],
    quality: 0.85,
  });

  if (result.canceled || !result.assets[0]) return null;

  const asset = result.assets[0];

  if (asset.mimeType && !ALLOWED_TYPES.includes(asset.mimeType)) {
    throw new Error('Invalid image type');
  }

  // Resize to MAX_WIDTH while preserving the 3:1 aspect; ImageManipulator
  // strips EXIF and re-encodes to JPEG.
  const manipulated = await ImageManipulator.manipulateAsync(
    asset.uri,
    [{ resize: { width: MAX_WIDTH } }],
    { compress: 0.85, format: ImageManipulator.SaveFormat.JPEG },
  );

  const base64 = await readAsStringAsync(manipulated.uri, {
    encoding: EncodingType.Base64,
  });

  // Magic-byte sanity check (same belt-and-suspenders pattern as
  // avatar-upload after AUDIT_SECURITY_2 M6).
  if (!base64.startsWith('/9j/')) {
    throw new Error('Invalid image type');
  }

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('Not authenticated');

  // Cache-bust by writing under a fresh UUID each time. Keeps the
  // current banner intact until the new one is fully uploaded; old
  // file gets orphaned in storage (we'll clean those in a sweep later).
  const objectName = `${user.id}/banner/${Date.now()}.jpg`;

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

  const bannerUrl = `${publicUrl}?t=${Date.now()}`;
  await proService.setBanner(bannerUrl);

  return bannerUrl;
}

export async function removeProBanner(): Promise<void> {
  await proService.setBanner(null);
}
