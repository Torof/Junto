-- Migration 00145: grant admin to scottpanam + scottintrip.
-- One-shot data migration. is_admin is whitelisted so set bypass_lock first.

DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users
  SET is_admin = TRUE
  WHERE display_name IN ('scottpanam', 'scottintrip');
END $$;
