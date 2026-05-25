-- Migration 00251: revoke_push_token_for_device — sign-out + perm-denied wiring.
--
-- The existing revoke_push_token(p_token) requires the client to know
-- the current Expo push token, which means caching it locally. The
-- client already persists a stable device_id in SecureStore (see
-- use-push-notifications.ts getOrCreateDeviceId), so revoking by
-- device is cleaner — no token cache, no race with token rotation,
-- and the OS-permission-denied case (where we can't query the OS for
-- the current token) is still serviceable.
--
-- Idempotent: silently no-ops if no token row exists for (caller,
-- p_device_id).

CREATE OR REPLACE FUNCTION revoke_push_token_for_device(p_device_id TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_revoked_token TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_device_id IS NULL OR char_length(p_device_id) < 1 OR char_length(p_device_id) > 100 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Capture whatever token is currently registered for this device so
  -- we can also clear the legacy users.push_token mirror below.
  SELECT token INTO v_revoked_token
  FROM push_tokens
  WHERE user_id = v_user_id AND device_id = p_device_id;

  DELETE FROM push_tokens
  WHERE user_id = v_user_id AND device_id = p_device_id;

  IF v_revoked_token IS NOT NULL THEN
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE users SET push_token = NULL
    WHERE id = v_user_id AND push_token = v_revoked_token;
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION revoke_push_token_for_device FROM anon;
GRANT EXECUTE ON FUNCTION revoke_push_token_for_device TO authenticated;
