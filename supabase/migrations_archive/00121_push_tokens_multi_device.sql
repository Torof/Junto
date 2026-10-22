-- Migration 00121: multi-device push tokens.
-- The single users.push_token column meant every new sign-in on a different
-- phone (or even the same account on a second phone) silently overwrote the
-- previous token — pushes went to the latest device only. Now we track tokens
-- per (user, device) so a user with phone + tablet, or two phones, gets push
-- on every active device.
--
-- A token can still only belong to ONE user at a time (the latest sign-in
-- claims it from any other user — same as before). A user can have N tokens.
--
-- users.push_token is kept in sync with the LATEST registered token for that
-- user as a fallback for any reader that hasn't been migrated to push_tokens
-- yet. The edge function reads from push_tokens.

-- ============================================================================
-- 1. push_tokens table
-- ============================================================================
CREATE TABLE IF NOT EXISTS push_tokens (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, token)
);

ALTER TABLE push_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE push_tokens FORCE ROW LEVEL SECURITY;

-- No client policies — only SECURITY DEFINER functions touch this.

-- Index for the edge function's per-user lookup
CREATE INDEX IF NOT EXISTS idx_push_tokens_user_id ON push_tokens (user_id);

-- ============================================================================
-- 2. Backfill from existing users.push_token values
-- ============================================================================
INSERT INTO push_tokens (user_id, token, created_at)
SELECT id, push_token, COALESCE(updated_at, now())
FROM users
WHERE push_token IS NOT NULL
ON CONFLICT (token) DO NOTHING;

-- ============================================================================
-- 3. register_push_token: claim token for current user, register without
--    displacing this user's other devices.
-- ============================================================================
CREATE OR REPLACE FUNCTION register_push_token(p_token TEXT)
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
  -- Other devices belonging to the same user are not touched.
  DELETE FROM push_tokens WHERE token = p_token AND user_id != v_user_id;

  -- Add this device to my list (idempotent for repeat registrations).
  INSERT INTO push_tokens (user_id, token) VALUES (v_user_id, p_token)
  ON CONFLICT (user_id, token) DO NOTHING;

  -- Legacy fallback: keep users.push_token in sync with the latest device.
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET push_token = NULL WHERE push_token = p_token AND id != v_user_id;
  UPDATE users SET push_token = p_token WHERE id = v_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION register_push_token FROM anon;
GRANT EXECUTE ON FUNCTION register_push_token TO authenticated;

-- ============================================================================
-- 4. Optional: explicit sign-out / token revocation per device.
-- ============================================================================
CREATE OR REPLACE FUNCTION revoke_push_token(p_token TEXT)
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

  DELETE FROM push_tokens WHERE user_id = v_user_id AND token = p_token;

  -- Clear users.push_token if it was pointing at this revoked token
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET push_token = NULL WHERE id = v_user_id AND push_token = p_token;
END;
$$;

REVOKE EXECUTE ON FUNCTION revoke_push_token FROM anon;
GRANT EXECUTE ON FUNCTION revoke_push_token TO authenticated;

-- ============================================================================
-- 5. Suspension trigger: clear ALL tokens, not just users.push_token.
-- ============================================================================
CREATE OR REPLACE FUNCTION clear_push_token_on_suspension()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET push_token = NULL WHERE id = NEW.id AND push_token IS NOT NULL;
  DELETE FROM push_tokens WHERE user_id = NEW.id;
  RETURN NEW;
END;
$$;
