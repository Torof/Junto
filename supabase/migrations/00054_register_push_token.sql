-- Migration 00054: RPC to register push notification tokens

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

  IF p_token IS NULL OR char_length(p_token) < 10 OR char_length(p_token) > 500 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET push_token = p_token WHERE id = v_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION register_push_token FROM anon;
GRANT EXECUTE ON FUNCTION register_push_token TO authenticated;
