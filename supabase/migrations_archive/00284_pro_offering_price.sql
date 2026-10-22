-- Migration 00284: optional indicative price on pro offerings.
--
-- "À partir de X € / pers|groupe" — display-only, zero payment expectation
-- (Junto is mise en relation; the transaction happens outside the app).
-- One floor price per offering: product variants are separate offerings
-- (the catalogue IS the price table), finer nuance (group discounts,
-- seasons) lives in the description.
--
-- price_eur / price_unit are NOT privileged columns (the pro edits his own
-- offering through update_pro_offering, same as title/level) — the 00249
-- whitelist trigger is untouched.
--
-- create/update_pro_offering gain two DEFAULT NULL params. CREATE OR REPLACE
-- with a different signature would create an OVERLOAD (PostgREST ambiguity),
-- so both old signatures are DROPped first and grants re-applied.

-- ============================================================================
-- 1. Columns
-- ============================================================================
ALTER TABLE pro_offerings
  ADD COLUMN price_eur NUMERIC
    CHECK (price_eur IS NULL OR (price_eur > 0 AND price_eur <= 99999)),
  ADD COLUMN price_unit TEXT
    CHECK (price_unit IS NULL OR price_unit IN ('person', 'group')),
  ADD CONSTRAINT pro_offerings_price_pair_chk
    CHECK ((price_eur IS NULL) = (price_unit IS NULL));

-- ============================================================================
-- 2. View — new columns appended at the END (CREATE OR REPLACE VIEW
--    requirement). Anon-granted since 00250; price is public display data.
-- ============================================================================
CREATE OR REPLACE VIEW pro_offerings_with_coords AS
SELECT
  o.id,
  o.pro_id,
  o.sport_id,
  o.title,
  o.description,
  o.level,
  o.location_name,
  o.duration,
  o.max_participants,
  o.schedule_text,
  o.distance_km,
  o.elevation_gain_m,
  (
    SELECT photo_url
    FROM pro_offering_photos p
    WHERE p.offering_id = o.id
    ORDER BY order_index ASC
    LIMIT 1
  ) AS image_url,
  o.created_at,
  o.updated_at,
  ST_X(o.location::geometry) AS lng,
  ST_Y(o.location::geometry) AS lat,
  s.key AS sport_key,
  s.icon AS sport_icon,
  s.category AS sport_category,
  pp.display_name AS pro_name,
  o.price_eur,
  o.price_unit
FROM pro_offerings o
JOIN sports s ON o.sport_id = s.id
JOIN pro_profiles pp ON o.pro_id = pp.user_id
WHERE NOT EXISTS (
  SELECT 1 FROM users u WHERE u.id = o.pro_id AND u.suspended_at IS NOT NULL
);

-- ============================================================================
-- 3. create_pro_offering — body copied VERBATIM from 00272 (latest), plus
--    p_price_eur / p_price_unit params, their validation, and the two
--    INSERT columns. Authorization chain unchanged.
-- ============================================================================
DROP FUNCTION create_pro_offering(UUID, TEXT, TEXT, TEXT, FLOAT, FLOAT, TEXT, TEXT, INTEGER, TEXT, NUMERIC, INTEGER);

CREATE FUNCTION create_pro_offering(
  p_sport_id UUID,
  p_title TEXT,
  p_description TEXT,
  p_level TEXT,
  p_location_lng FLOAT,
  p_location_lat FLOAT,
  p_location_name TEXT,
  p_duration TEXT DEFAULT NULL,
  p_max_participants INTEGER DEFAULT NULL,
  p_schedule_text TEXT DEFAULT NULL,
  p_distance_km NUMERIC DEFAULT NULL,
  p_elevation_gain_m INTEGER DEFAULT NULL,
  p_price_eur NUMERIC DEFAULT NULL,
  p_price_unit TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_tier TEXT;
  v_count INTEGER;
  v_offering_id UUID;
  v_clean_title TEXT;
  v_clean_location_name TEXT;
  v_clean_schedule TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT tier INTO v_tier FROM users WHERE id = v_user_id;
  IF v_tier IS DISTINCT FROM 'pro' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_title := trim(p_title);
  IF char_length(v_clean_title) < 3 OR char_length(v_clean_title) > 100 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_description IS NULL OR char_length(p_description) > 2000 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_level IS NULL OR char_length(trim(p_level)) < 1 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_location_name := trim(p_location_name);
  IF char_length(v_clean_location_name) < 1 OR char_length(v_clean_location_name) > 100 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_location_lng IS NULL OR p_location_lat IS NULL
     OR p_location_lng < -180 OR p_location_lng > 180
     OR p_location_lat < -90 OR p_location_lat > 90 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_max_participants IS NOT NULL AND (p_max_participants < 1 OR p_max_participants > 50) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_schedule_text IS NOT NULL THEN
    v_clean_schedule := trim(p_schedule_text);
    IF char_length(v_clean_schedule) > 100 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF char_length(v_clean_schedule) = 0 THEN
      v_clean_schedule := NULL;
    END IF;
  END IF;

  IF p_distance_km IS NOT NULL AND (p_distance_km <= 0 OR p_distance_km > 9999) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_elevation_gain_m IS NOT NULL AND (p_elevation_gain_m <= 0 OR p_elevation_gain_m > 99999) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_price_eur IS NOT NULL AND (p_price_eur <= 0 OR p_price_eur > 99999) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_price_unit IS NOT NULL AND p_price_unit NOT IN ('person', 'group') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF (p_price_eur IS NULL) <> (p_price_unit IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('create_offering:' || v_user_id::text));

  SELECT count(*) INTO v_count
  FROM pro_offerings
  WHERE pro_id = v_user_id;

  -- 12: covers the typical catalogue, forces curation, and keeps the
  -- permanent-pin density on the map under control (RA pins accumulate,
  -- UA pins expire). Raise later if real pros ask — never lower.
  IF v_count >= 12 THEN RAISE EXCEPTION 'junto.offering_cap'; END IF;

  INSERT INTO pro_offerings (
    pro_id, sport_id, title, description, level,
    location, location_name,
    duration, max_participants, schedule_text,
    distance_km, elevation_gain_m,
    price_eur, price_unit,
    created_at, updated_at
  ) VALUES (
    v_user_id, p_sport_id, v_clean_title, p_description, p_level,
    ST_SetSRID(ST_MakePoint(p_location_lng, p_location_lat), 4326)::geography,
    v_clean_location_name,
    CASE WHEN p_duration IS NOT NULL THEN p_duration::interval ELSE NULL END,
    p_max_participants,
    v_clean_schedule,
    p_distance_km,
    p_elevation_gain_m,
    p_price_eur,
    p_price_unit,
    now(), now()
  ) RETURNING id INTO v_offering_id;

  RETURN v_offering_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_pro_offering FROM anon;
GRANT EXECUTE ON FUNCTION create_pro_offering TO authenticated;

-- ============================================================================
-- 4. update_pro_offering — body copied VERBATIM from 00249 (latest), plus
--    the price params/validation/SET. Authorization chain unchanged.
-- ============================================================================
DROP FUNCTION update_pro_offering(UUID, UUID, TEXT, TEXT, TEXT, FLOAT, FLOAT, TEXT, TEXT, INTEGER, TEXT, NUMERIC, INTEGER);

CREATE FUNCTION update_pro_offering(
  p_offering_id UUID,
  p_sport_id UUID,
  p_title TEXT,
  p_description TEXT,
  p_level TEXT,
  p_location_lng FLOAT,
  p_location_lat FLOAT,
  p_location_name TEXT,
  p_duration TEXT DEFAULT NULL,
  p_max_participants INTEGER DEFAULT NULL,
  p_schedule_text TEXT DEFAULT NULL,
  p_distance_km NUMERIC DEFAULT NULL,
  p_elevation_gain_m INTEGER DEFAULT NULL,
  p_price_eur NUMERIC DEFAULT NULL,
  p_price_unit TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_tier TEXT;
  v_clean_title TEXT;
  v_clean_location_name TEXT;
  v_clean_schedule TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT tier INTO v_tier FROM users WHERE id = v_user_id;
  IF v_tier IS DISTINCT FROM 'pro' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Ownership check
  IF NOT EXISTS (
    SELECT 1 FROM pro_offerings WHERE id = p_offering_id AND pro_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Input validation (identical to create)
  v_clean_title := trim(p_title);
  IF char_length(v_clean_title) < 3 OR char_length(v_clean_title) > 100 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_description IS NULL OR char_length(p_description) > 2000 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_level IS NULL OR char_length(trim(p_level)) < 1 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_location_name := trim(p_location_name);
  IF char_length(v_clean_location_name) < 1 OR char_length(v_clean_location_name) > 100 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_location_lng IS NULL OR p_location_lat IS NULL
     OR p_location_lng < -180 OR p_location_lng > 180
     OR p_location_lat < -90 OR p_location_lat > 90 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_max_participants IS NOT NULL AND (p_max_participants < 1 OR p_max_participants > 50) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_schedule_text IS NOT NULL THEN
    v_clean_schedule := trim(p_schedule_text);
    IF char_length(v_clean_schedule) > 100 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF char_length(v_clean_schedule) = 0 THEN
      v_clean_schedule := NULL;
    END IF;
  END IF;

  IF p_distance_km IS NOT NULL AND (p_distance_km <= 0 OR p_distance_km > 9999) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_elevation_gain_m IS NOT NULL AND (p_elevation_gain_m <= 0 OR p_elevation_gain_m > 99999) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_price_eur IS NOT NULL AND (p_price_eur <= 0 OR p_price_eur > 99999) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_price_unit IS NOT NULL AND p_price_unit NOT IN ('person', 'group') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF (p_price_eur IS NULL) <> (p_price_unit IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  UPDATE pro_offerings SET
    sport_id = p_sport_id,
    title = v_clean_title,
    description = p_description,
    level = p_level,
    location = ST_SetSRID(ST_MakePoint(p_location_lng, p_location_lat), 4326)::geography,
    location_name = v_clean_location_name,
    duration = CASE WHEN p_duration IS NOT NULL THEN p_duration::interval ELSE NULL END,
    max_participants = p_max_participants,
    schedule_text = v_clean_schedule,
    distance_km = p_distance_km,
    elevation_gain_m = p_elevation_gain_m,
    price_eur = p_price_eur,
    price_unit = p_price_unit
  WHERE id = p_offering_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION update_pro_offering FROM anon;
GRANT EXECUTE ON FUNCTION update_pro_offering TO authenticated;
