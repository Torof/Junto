-- ============================================================================
-- 00461 — Sixth universe « Bien-être » + seven sports (Scott 2026-10-19).
--
--   wellness : yoga · tai-chi · qi-gong · meditation
--   on-foot  : nordic-walking
--   water    : kitesurfing · wingfoil
--
-- sports.category is free text (no CHECK) — a new universe is pure data, the
-- same way 00282 added 'on-foot'. Nothing server-side branches on category
-- (award aggregates group by it generically). Colour / icons / labels live in
-- the app (sport-category-color.ts, sport-universe.ts, sport-icon-svgs.ts).
--
-- Pro pushpin: the pin_icon universe set grows 4 -> 5 so a wellness pro
-- (yoga teacher) can show a sand disc. Scott validated 2026-10-19. The
-- set_pro_pin_icon auth chain (auth -> suspension -> approved pro) is
-- unchanged, rebuilt from its live definition (identical to 00281); only the
-- allowed value set changes.
--
-- No gear_catalog rows (same as 00414) ; generic level scale client-side ;
-- nordic-walking joins the distance + D+ sports.
-- ============================================================================

INSERT INTO sports (key, icon, category, display_order, is_active) VALUES
  ('yoga',           'yoga',           'wellness', 45, true),
  ('tai-chi',        'tai-chi',        'wellness', 46, true),
  ('qi-gong',        'qi-gong',        'wellness', 47, true),
  ('meditation',     'meditation',     'wellness', 48, true),
  ('nordic-walking', 'nordic-walking', 'on-foot',  49, true),
  ('kitesurfing',    'kitesurfing',    'water',    50, true),
  ('wingfoil',       'wingfoil',       'water',    51, true)
ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Pro pushpin universes: + 'wellness'
-- ---------------------------------------------------------------------------
ALTER TABLE pro_profiles DROP CONSTRAINT IF EXISTS pro_profiles_pin_icon_check;
ALTER TABLE pro_profiles ADD CONSTRAINT pro_profiles_pin_icon_check
  CHECK (pin_icon IS NULL OR pin_icon IN ('mountain', 'water', 'air', 'cycling', 'wellness'));

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
  IF p_pin_icon IS NOT NULL AND p_pin_icon NOT IN ('mountain', 'water', 'air', 'cycling', 'wellness') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  UPDATE pro_profiles SET pin_icon = p_pin_icon WHERE user_id = v_user_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION set_pro_pin_icon(TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION set_pro_pin_icon(TEXT) TO authenticated;
