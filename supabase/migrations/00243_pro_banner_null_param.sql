-- Migration 00243: set_pro_banner — accept NULL by default.
--
-- 00242 declared p_banner_url TEXT without a default, which makes the
-- Supabase-generated TypeScript type non-nullable. Clients clearing
-- the banner have to send the empty string and we coerce server-side.
-- Cleaner to declare a NULL default so the param is properly optional
-- AND the generated type allows undefined.

DROP FUNCTION IF EXISTS set_pro_banner(TEXT);

CREATE FUNCTION set_pro_banner(p_banner_url TEXT DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_banner_url IS NOT NULL AND char_length(p_banner_url) > 500 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE pro_profiles SET banner_url = p_banner_url WHERE user_id = v_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION set_pro_banner(TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION set_pro_banner(TEXT) TO authenticated;
