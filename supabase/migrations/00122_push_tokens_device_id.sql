-- Migration 00122: dedupe push tokens per (user, device).
-- The previous design had no way to tell "this is a new Expo token for the
-- same physical device" (caused by app reinstalls, OS-level token rotations,
-- dev rebuilds) from "this is a different device". Result: a single phone
-- could end up with multiple tokens registered, causing duplicate push
-- notifications on the same device.
--
-- Fix: client generates and persists a UUID once per install. Server keeps
-- one row per (user_id, device_id). Re-registering with the same device_id
-- replaces the old token in place.

-- ============================================================================
-- 1. device_id column + uniqueness per (user, device)
-- ============================================================================
ALTER TABLE push_tokens ADD COLUMN IF NOT EXISTS device_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS push_tokens_user_device_idx
  ON push_tokens (user_id, device_id)
  WHERE device_id IS NOT NULL;

-- ============================================================================
-- 2. One-time prune: keep only the MOST RECENT token per user.
--    Devices will re-register cleanly on next app-open with their device_id.
-- ============================================================================
DELETE FROM push_tokens
WHERE (user_id, created_at) NOT IN (
  SELECT user_id, MAX(created_at) FROM push_tokens GROUP BY user_id
);

-- ============================================================================
-- 3. register_push_token: dedupe by (user, device_id) when provided
-- ============================================================================
-- Drop prior single-param signature so REVOKE/GRANT below isn't ambiguous.
DROP FUNCTION IF EXISTS register_push_token(TEXT);

CREATE OR REPLACE FUNCTION register_push_token(
  p_token TEXT,
  p_device_id TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_token IS NULL OR char_length(p_token) < 20 OR char_length(p_token) > 200 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_token !~ '^Exp(o|onent)PushToken\[.+\]$' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Detach this token from any OTHER user (a phone just signed in as me).
  DELETE FROM push_tokens WHERE token = p_token AND user_id != v_user_id;

  IF p_device_id IS NOT NULL THEN
    -- Replace any prior token registered for this device under my account.
    DELETE FROM push_tokens
      WHERE user_id = v_user_id
        AND device_id = p_device_id
        AND token != p_token;
    -- Insert or update the row for this (user, device).
    INSERT INTO push_tokens (user_id, token, device_id)
      VALUES (v_user_id, p_token, p_device_id)
      ON CONFLICT (user_id, token)
      DO UPDATE SET device_id = EXCLUDED.device_id;
  ELSE
    INSERT INTO push_tokens (user_id, token)
      VALUES (v_user_id, p_token)
      ON CONFLICT (user_id, token) DO NOTHING;
  END IF;

  -- Legacy fallback: keep users.push_token aligned with the latest device.
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET push_token = NULL WHERE push_token = p_token AND id != v_user_id;
  UPDATE users SET push_token = p_token WHERE id = v_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION register_push_token FROM anon;
GRANT EXECUTE ON FUNCTION register_push_token TO authenticated;
