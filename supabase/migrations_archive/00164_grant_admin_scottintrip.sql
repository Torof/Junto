-- Migration 00164: re-grant admin to scottintrip@gmail.com.
--
-- One-shot data migration. Mig 00145 originally granted admin via
-- display_name = 'scottintrip', but the test account currently hits the
-- 20-activities-per-day cap in create_activity, meaning is_admin isn't
-- set on it (display_name probably differs from 'scottintrip' on this
-- account, or was never set during 00145).
--
-- Look up by email instead — auth.users.email is the stable identifier
-- regardless of profile state. is_admin is whitelisted; bypass_lock
-- before the UPDATE.

DO $$
DECLARE
  v_user_id UUID;
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  SELECT id INTO v_user_id
  FROM auth.users
  WHERE email = 'scottintrip@gmail.com';

  IF v_user_id IS NOT NULL THEN
    UPDATE users SET is_admin = TRUE WHERE id = v_user_id;
  END IF;
END $$;
