-- Migration 00241: storage bucket for pro photos.
--
-- Phase 0.5 of the Pro feature. One bucket — `pro-photos` — covers
-- both the pro page gallery AND recurring-activity galleries. Path
-- schema enforces ownership via auth.uid():
--   {user_id}/profile/{uuid}.jpg          → pro page photo
--   {user_id}/activity/{activity_id}/{uuid}.jpg → recurring activity photo
--
-- Public read (it's a business surface); writes scoped to the owner.
-- 25-photo cap per surface is enforced client-side + via INSERT count
-- checks in the upload RPC we'll add in Phase 4; storage layer is
-- intentionally permissive on count so a temporarily-over cap doesn't
-- become an unrecoverable state.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'pro-photos',
  'pro-photos',
  true,
  5242880,  -- 5 MB per file
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "pro_photos_read_all" ON storage.objects;
DROP POLICY IF EXISTS "pro_photos_insert_own" ON storage.objects;
DROP POLICY IF EXISTS "pro_photos_update_own" ON storage.objects;
DROP POLICY IF EXISTS "pro_photos_delete_own" ON storage.objects;

-- Public read — pro photos are part of the public business surface.
CREATE POLICY "pro_photos_read_all"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'pro-photos');

-- Authenticated users can only upload under their own user_id folder.
-- Suspended-user check happens at the RPC layer (the photo metadata
-- INSERT in Phase 4) — storage RLS keeps the path constraint as the
-- only object-level guard.
CREATE POLICY "pro_photos_insert_own"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'pro-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "pro_photos_update_own"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'pro-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "pro_photos_delete_own"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'pro-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
