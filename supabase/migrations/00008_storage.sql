-- Migration 00008: storage buckets and policies

-- ============================================================================
-- BUCKET: avatars (public — visible to everyone)
-- Path convention: /avatars/{user_id}/avatar (fixed name, overwrites old)
-- ============================================================================
INSERT INTO storage.buckets (id, name, public) VALUES ('avatars', 'avatars', true);

-- Anyone can read (public bucket)
CREATE POLICY "avatars_read_all"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');

-- Authenticated users upload to their own folder only
CREATE POLICY "avatars_insert_own"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

-- Authenticated users update their own avatar
CREATE POLICY "avatars_update_own"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

-- Authenticated users delete their own avatar
CREATE POLICY "avatars_delete_own"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

-- NOTE: pro-documents bucket created in Sprint 6 (not needed until then)
