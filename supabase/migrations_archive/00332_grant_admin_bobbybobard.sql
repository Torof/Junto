-- Migration 00332: grant admin to bobbybobard0@gmail.com — bootstrap admin.
-- The pre-launch purge (00331) wiped every account, so nobody is admin and no
-- one can approve pros. This re-establishes an admin. is_admin is a privileged
-- column (handle_user_update forces it to OLD), so the UPDATE runs under
-- bypass_lock. Fails loudly if the account doesn't exist yet (so we don't
-- silently mark this migration applied on a no-op).
DO $$
DECLARE
  v_id UUID;
BEGIN
  SELECT id INTO v_id
  FROM public.users
  WHERE lower(email) = lower('bobbybobard0@gmail.com');

  IF v_id IS NULL THEN
    RAISE EXCEPTION '[00332] account bobbybobard0@gmail.com NOT FOUND — has it signed up yet?';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE public.users SET is_admin = TRUE WHERE id = v_id;

  RAISE NOTICE '[00332] is_admin set TRUE for bobbybobard0@gmail.com (id=%)', v_id;
END $$;
