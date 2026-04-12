import * as ImagePicker from 'expo-image-picker';
import * as ImageManipulator from 'expo-image-manipulator';
import { supabase } from '@/services/supabase';

const MAX_SIZE = 400;
const MAX_FILE_SIZE = 5 * 1024 * 1024; // 5MB

const ALLOWED_TYPES = ['image/jpeg', 'image/png', 'image/webp'];

export async function pickAndUploadAvatar(): Promise<string | null> {
  // 1. Pick image from gallery
  const result = await ImagePicker.launchImageLibraryAsync({
    mediaTypes: ['images'],
    allowsEditing: true,
    aspect: [1, 1],
    quality: 0.8,
  });

  if (result.canceled || !result.assets[0]) return null;

  const asset = result.assets[0];

  // 2. Validate type
  if (asset.mimeType && !ALLOWED_TYPES.includes(asset.mimeType)) {
    throw new Error('Invalid image type');
  }

  // 3. Resize + strip EXIF (ImageManipulator removes EXIF by default)
  const manipulated = await ImageManipulator.manipulateAsync(
    asset.uri,
    [{ resize: { width: MAX_SIZE, height: MAX_SIZE } }],
    { compress: 0.8, format: ImageManipulator.SaveFormat.JPEG },
  );

  // 4. Read as blob
  const response = await fetch(manipulated.uri);
  const blob = await response.blob();

  if (blob.size > MAX_FILE_SIZE) {
    throw new Error('File too large');
  }

  // 5. Get user ID
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error('Not authenticated');

  const path = `${user.id}/avatar`;

  // 6. Upload (upsert — overwrites existing)
  const { error: uploadError } = await supabase.storage
    .from('avatars')
    .upload(path, blob, {
      contentType: 'image/jpeg',
      upsert: true,
    });

  if (uploadError) throw uploadError;

  // 7. Get public URL
  const { data: { publicUrl } } = supabase.storage
    .from('avatars')
    .getPublicUrl(path);

  // 8. Update user profile with cache-busting query param
  const avatarUrl = `${publicUrl}?t=${Date.now()}`;
  const { error: updateError } = await supabase
    .from('users')
    .update({ avatar_url: avatarUrl })
    .eq('id', user.id);

  if (updateError) throw updateError;

  return avatarUrl;
}
