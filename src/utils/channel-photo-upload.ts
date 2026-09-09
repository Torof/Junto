import * as ImagePicker from 'expo-image-picker';
import * as ImageManipulator from 'expo-image-manipulator';
import { readAsStringAsync, EncodingType } from 'expo-file-system/legacy';
import { decode } from 'base64-arraybuffer';
import { supabase } from '@/services/supabase';

// Channel photo = a wide banner behind the list card → crop 3:2, resize to a
// modest width (it renders faintly). Mirrors avatar-upload.ts: pick → crop →
// resize + EXIF strip → magic-byte check → upload to the owner's folder in the
// `channel-photos` bucket. Returns the public URL (the caller then hands it to
// create_channel / set_channel_photo, which is where creator-ownership is
// enforced). Object path stays {uid}/… as required by the bucket's write policy.
const MAX_WIDTH = 1200;
const ALLOWED_TYPES = ['image/jpeg', 'image/png', 'image/webp'];

export async function pickAndUploadChannelPhoto(): Promise<string | null> {
  const result = await ImagePicker.launchImageLibraryAsync({
    mediaTypes: ['images'],
    allowsEditing: true,
    aspect: [3, 2],
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

  const base64 = await readAsStringAsync(manipulated.uri, { encoding: EncodingType.Base64 });
  if (!base64.startsWith('/9j/')) {
    throw new Error('Invalid image type');
  }

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('Not authenticated');

  const objectName = `${user.id}/channels/${Date.now()}.jpg`;
  const { error: uploadError } = await supabase.storage
    .from('channel-photos')
    .upload(objectName, decode(base64), { contentType: 'image/jpeg', upsert: true });
  if (uploadError) throw uploadError;

  const { data: { publicUrl } } = supabase.storage.from('channel-photos').getPublicUrl(objectName);
  return `${publicUrl}?t=${Date.now()}`;
}
