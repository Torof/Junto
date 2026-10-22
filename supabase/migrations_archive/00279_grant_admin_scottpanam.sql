-- Migration 00279: grant admin to scottpanam@protonmail.com (Scott's dev/test
-- account). Needed to access the admin hub (moderation + pro approvals) and to
-- test the pro-approval flow on the dev device. is_admin is a privileged column
-- (handle_user_update forces it to OLD), so the UPDATE runs under bypass_lock.
DO $$
DECLARE
  v_id UUID;
  v_admin BOOLEAN;
BEGIN
  SELECT id, coalesce(is_admin, FALSE) INTO v_id, v_admin
  FROM public.users WHERE email = 'scottpanam@protonmail.com';

  IF v_id IS NULL THEN
    RAISE NOTICE '[00279] account scottpanam@protonmail.com NOT FOUND';
    RETURN;
  END IF;

  RAISE NOTICE '[00279] before: is_admin=%', v_admin;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE public.users SET is_admin = TRUE WHERE id = v_id;

  RAISE NOTICE '[00279] is_admin set TRUE for scottpanam@protonmail.com';
END $$;
