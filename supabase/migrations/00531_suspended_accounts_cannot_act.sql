-- 00531 — a suspended account can no longer block, upload files or edit its
-- profile through the table/storage policies (audit 2026-10-23, identity F3/F4).
--
-- * blocked_users INSERT: a suspended account's block still withdrew a third
--   party's join request and sent the organiser a notice.
-- * storage (avatars, pro-photos, channel-photos) INSERT/UPDATE: a suspended
--   account kept 150 public 5 MB files a day on the project domain.
-- * users UPDATE (own profile): a suspended account could still edit its bio.
-- private.user_is_suspended is already EXECUTE for authenticated (RLS use).

DROP POLICY IF EXISTS blocked_users_insert_own ON public.blocked_users;
CREATE POLICY blocked_users_insert_own ON public.blocked_users
  FOR INSERT TO authenticated
  WITH CHECK (blocker_id = auth.uid() AND NOT private.user_is_suspended(auth.uid()));

DROP POLICY IF EXISTS users_update_own ON public.users;
CREATE POLICY users_update_own ON public.users
  FOR UPDATE TO authenticated
  USING (auth.uid() = id AND NOT private.user_is_suspended(auth.uid()))
  WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS avatars_insert_own ON storage.objects;
CREATE POLICY avatars_insert_own ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text
              AND NOT private.user_is_suspended(auth.uid()));
DROP POLICY IF EXISTS avatars_update_own ON storage.objects;
CREATE POLICY avatars_update_own ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text
         AND NOT private.user_is_suspended(auth.uid()));

DROP POLICY IF EXISTS channel_photos_insert_own ON storage.objects;
CREATE POLICY channel_photos_insert_own ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'channel-photos' AND (storage.foldername(name))[1] = auth.uid()::text
              AND NOT private.user_is_suspended(auth.uid()));
DROP POLICY IF EXISTS channel_photos_update_own ON storage.objects;
CREATE POLICY channel_photos_update_own ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'channel-photos' AND (storage.foldername(name))[1] = auth.uid()::text
         AND NOT private.user_is_suspended(auth.uid()));

DROP POLICY IF EXISTS pro_photos_insert_own ON storage.objects;
CREATE POLICY pro_photos_insert_own ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'pro-photos' AND (storage.foldername(name))[1] = auth.uid()::text
              AND NOT private.user_is_suspended(auth.uid()));
DROP POLICY IF EXISTS pro_photos_update_own ON storage.objects;
CREATE POLICY pro_photos_update_own ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'pro-photos' AND (storage.foldername(name))[1] = auth.uid()::text
         AND NOT private.user_is_suspended(auth.uid()));
