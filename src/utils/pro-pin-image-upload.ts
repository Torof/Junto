import * as ImagePicker from 'expo-image-picker';
import * as ImageManipulator from 'expo-image-manipulator';
import { readAsStringAsync, EncodingType } from 'expo-file-system/legacy';
import { decode } from 'base64-arraybuffer';
import { supabase } from '@/services/supabase';
import { proService } from '@/services/pro-service';

// Small square — shown inside the pro pin on the map. Doesn't need
// to be much bigger than the pin renders at (~80dp × pixel ratio).
const MAX_SIZE = 240;
const ALLOWED_TYPES = ['image/jpeg', 'image/png', 'image/webp'];

// `apply` (default true) also writes the URL on the profile right away. The
// edit screen passes false: the upload happens at pick time, the profile
// change waits for « Enregistrer » with everything else (lot 2 pro, Scott
// 2026-10-15 — one save logic, not two).
export async function pickAndUploadProPinImage(apply = true): Promise<string | null> {
  const result = await ImagePicker.launchImageLibraryAsync({
    mediaTypes: ['images'],
    allowsEditing: true,
    aspect: [1, 1],
    quality: 0.85,
  });

  if (result.canceled || !result.assets[0]) return null;

  const asset = result.assets[0];

  if (asset.mimeType && !ALLOWED_TYPES.includes(asset.mimeType)) {
    throw new Error('Invalid image type');
  }

  const manipulated = await ImageManipulator.manipulateAsync(
    asset.uri,
    [{ resize: { width: MAX_SIZE, height: MAX_SIZE } }],
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

  const objectName = `${user.id}/pin/${Date.now()}.jpg`;

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

  const pinUrl = `${publicUrl}?t=${Date.now()}`;
  if (apply) await proService.setPinImage(pinUrl);

  return pinUrl;
}

