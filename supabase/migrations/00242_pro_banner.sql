-- Migration 00242: pro page banner.
--
-- Adds a single banner_url column on pro_profiles + a dedicated
-- set_pro_banner RPC. Standalone RPC (rather than threading p_banner_url
-- through update_pro_profile) so the banner upload flow stays small
-- and decoupled — banner changes are frequent / atomic, the rest of
-- the profile edits are not.

ALTER TABLE pro_profiles
  ADD COLUMN banner_url TEXT CHECK (banner_url IS NULL OR char_length(banner_url) <= 500);

-- ============================================================================
-- set_pro_banner — owner-only banner URL setter. NULL clears it.
-- Auth chain mirrors update_pro_profile: auth → suspended → owns row
-- → length check → write. Privileged columns on pro_profiles stay
-- locked via the whitelist trigger; banner_url is non-privileged.
-- ============================================================================
CREATE OR REPLACE FUNCTION set_pro_banner(p_banner_url TEXT)
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

REVOKE EXECUTE ON FUNCTION set_pro_banner FROM anon;
GRANT EXECUTE ON FUNCTION set_pro_banner TO authenticated;
