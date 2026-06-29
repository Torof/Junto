-- ============================================================================
-- Migration 00281: Universe taxonomy v2.
--
-- Junto's single test for a sport: "will people look for PARTNERS for it?"
-- That collapses the old 8 ad-hoc categories into 5 coherent peer universes
-- (mountain · water · air · cycling · running) and soft-retires the 15 sports
-- that fail the test (club/court/gym, solo-parallel, or heavy-booking).
-- Pro pushpins use a 4-universe subset (no "running" — no running guides exist).
--
-- Re-maps categories, adds is_active (soft-retire; hard delete happens at the
-- launch data-wipe), adds trekking + canoe, and narrows pin_icon 8 -> 4 with a
-- defensive remap so the new CHECK can't abort on a stale value.
-- Icons / level scales / i18n / colors live in the client.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Soft-retire flag (admin-only table; no client writes, no trigger needed)
-- ---------------------------------------------------------------------------
ALTER TABLE sports ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT true;

-- ---------------------------------------------------------------------------
-- 2. Re-map categories to the 5 universes.
--    Only the moves are listed; mountain (snow/climb), water and air sports
--    already carry the right value.
--      road  -> cycling (bikes) + running (foot)
--      mountain(mtb) -> cycling
--      water(canyon) / outdoor(caving) -> mountain
-- ---------------------------------------------------------------------------
UPDATE sports SET category = 'cycling'
  WHERE key IN ('cycling', 'gravel', 'mtb-xc', 'mtb-enduro', 'mtb-downhill');
UPDATE sports SET category = 'running'
  WHERE key IN ('running', 'trail-running');
UPDATE sports SET category = 'mountain'
  WHERE key IN ('canyoning', 'caving');

-- ---------------------------------------------------------------------------
-- 3. Soft-retire the sports that fail the partner-search test.
-- ---------------------------------------------------------------------------
UPDATE sports SET is_active = false WHERE key IN (
  'football', 'tennis', 'volleyball', 'badminton',   -- ball: club / court / league
  'crossfit', 'triathlon',                           -- gym / competition training
  'skateboarding',                                   -- urban, solo
  'horseback-riding', 'nordic-walking',              -- centre / club, weak partner pull
  'slacklining', 'highlining',                       -- park / heavy rigging, niche
  'rock-fishing',                                    -- solo hobby
  'kitesurf', 'windsurf', 'wakeboard'                -- parallel-solo / cable-park facility
);

-- ---------------------------------------------------------------------------
-- 4. Add the two new partner-sports.
-- ---------------------------------------------------------------------------
INSERT INTO sports (key, icon, category, display_order, is_active) VALUES
  ('trekking', 'trekking', 'mountain', 40, true),
  ('canoe',    'canoe',    'water',    41, true);

-- ---------------------------------------------------------------------------
-- 5. Gear catalog — tag the new sports onto existing shared items so they
--    aren't empty (guarded append, no duplicates).
-- ---------------------------------------------------------------------------
UPDATE gear_catalog SET sport_keys = array_append(sport_keys, 'trekking')
  WHERE name_key IN ('Eau / Gourde', 'Trousse de secours', 'Lampe frontale', 'Bâtons')
    AND NOT ('trekking' = ANY(sport_keys));
UPDATE gear_catalog SET sport_keys = array_append(sport_keys, 'canoe')
  WHERE name_key IN ('Gilet de sauvetage', 'Combinaison', 'Casque')
    AND NOT ('canoe' = ANY(sport_keys));

-- ---------------------------------------------------------------------------
-- 6. pin_icon: defensive remap of the old 8-set onto the new 4, NULL anything
--    that can't map, then narrow the CHECK. Order matters — remap before CHECK.
-- ---------------------------------------------------------------------------
UPDATE pro_profiles SET pin_icon = CASE pin_icon
    WHEN 'cliff'  THEN 'mountain'
    WHEN 'snow'   THEN 'mountain'
    WHEN 'forest' THEN 'mountain'
    WHEN 'sea'    THEN 'water'
    WHEN 'river'  THEN 'water'
    WHEN 'bike'   THEN 'cycling'
    ELSE pin_icon
  END
  WHERE pin_icon IN ('cliff', 'snow', 'forest', 'sea', 'river', 'bike');

UPDATE pro_profiles SET pin_icon = NULL
  WHERE pin_icon IS NOT NULL
    AND pin_icon NOT IN ('mountain', 'water', 'air', 'cycling');

ALTER TABLE pro_profiles DROP CONSTRAINT IF EXISTS pro_profiles_pin_icon_check;
ALTER TABLE pro_profiles ADD CONSTRAINT pro_profiles_pin_icon_check
  CHECK (pin_icon IS NULL OR pin_icon IN ('mountain', 'water', 'air', 'cycling'));

-- ---------------------------------------------------------------------------
-- 7. set_pro_pin_icon — auth chain unchanged (auth -> suspension -> approved),
--    only the allowed value set narrows 8 -> 4.
-- ---------------------------------------------------------------------------
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
  IF p_pin_icon IS NOT NULL AND p_pin_icon NOT IN ('mountain', 'water', 'air', 'cycling') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  UPDATE pro_profiles SET pin_icon = p_pin_icon WHERE user_id = v_user_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION set_pro_pin_icon(TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION set_pro_pin_icon(TEXT) TO authenticated;
