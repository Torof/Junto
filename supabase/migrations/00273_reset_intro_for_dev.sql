-- Migration 00273: one-off dev-data reset — clear tutorial_seen_at for the
-- dev account so the new intro carousel shows again on next map open.
-- tutorial_seen_at is a privileged column (normally only mark_tutorial_seen
-- sets it), so we bypass the whitelist trigger the same way the function does.
-- Guarded by email lookup; no-op on any DB where that account doesn't exist.

DO $$
DECLARE
  v_id UUID;
  v_n INTEGER;
BEGIN
  SELECT id INTO v_id FROM auth.users WHERE email = 'dev.solidity@proton.me';
  IF v_id IS NULL THEN
    RAISE NOTICE 'reset_intro: no account for that email — skipping';
    RETURN;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET tutorial_seen_at = NULL WHERE id = v_id;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RAISE NOTICE 'reset_intro: cleared tutorial_seen_at for % (rows=%)', v_id, v_n;
END $$;
