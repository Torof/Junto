-- Migration 00280: the pro page pushpin shows a chosen ENVIRONMENT icon
-- instead of a photo (pin system v4). Adds pin_icon — one of a curated set —
-- plus a setter mirroring set_pro_pin_image (00278). pin_icon is a
-- non-privileged, pro-editable column: it is NOT listed in the pro_profiles
-- whitelist trigger (pro_profiles_whitelist_columns), so it flows through
-- normally; no trigger change needed.

ALTER TABLE pro_profiles
  ADD COLUMN pin_icon TEXT
  CHECK (pin_icon IS NULL OR pin_icon IN
    ('mountain', 'cliff', 'sea', 'river', 'air', 'snow', 'bike', 'forest'));

-- Setter: an approved pro sets their own pushpin icon. Mirrors
-- set_pro_pin_image exactly (auth → suspension → approved → value check).
CREATE OR REPLACE FUNCTION set_pro_pin_icon(p_pin_icon TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id AND status = 'approved') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_pin_icon IS NOT NULL AND p_pin_icon NOT IN
    ('mountain', 'cliff', 'sea', 'river', 'air', 'snow', 'bike', 'forest') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  UPDATE pro_profiles SET pin_icon = p_pin_icon WHERE user_id = v_user_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION set_pro_pin_icon(TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION set_pro_pin_icon(TEXT) TO authenticated;
