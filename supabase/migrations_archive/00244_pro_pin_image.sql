-- Migration 00244: pro pin image.
--
-- Adds pin_image_url on pro_profiles + a set_pro_pin_image RPC. This
-- is the small square image displayed *inside* the map pin (replacing
-- the initial letter when set). Distinct from banner_url (the 3:1
-- magazine cover on the pro page).

ALTER TABLE pro_profiles
  ADD COLUMN pin_image_url TEXT CHECK (pin_image_url IS NULL OR char_length(pin_image_url) <= 500);

CREATE FUNCTION set_pro_pin_image(p_pin_image_url TEXT DEFAULT NULL)
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

  IF p_pin_image_url IS NOT NULL AND char_length(p_pin_image_url) > 500 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE pro_profiles SET pin_image_url = p_pin_image_url WHERE user_id = v_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION set_pro_pin_image(TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION set_pro_pin_image(TEXT) TO authenticated;
