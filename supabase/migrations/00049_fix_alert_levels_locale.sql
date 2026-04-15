-- Migration 00049: fix create_alert level validation (French values)

CREATE OR REPLACE FUNCTION create_alert(
  p_lng FLOAT,
  p_lat FLOAT,
  p_radius_km INTEGER,
  p_sport_key TEXT DEFAULT NULL,
  p_levels TEXT[] DEFAULT NULL,
  p_starts_on DATE DEFAULT NULL,
  p_ends_on DATE DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_tier TEXT;
  v_alert_count INTEGER;
  v_alert_id UUID;
  v_allowed_levels TEXT[] := ARRAY['débutant', 'intermédiaire', 'avancé', 'expert'];
  v_level TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT tier INTO v_tier FROM users WHERE id = v_user_id;
  IF v_tier NOT IN ('premium', 'pro') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT count(*) INTO v_alert_count FROM activity_alerts WHERE user_id = v_user_id;
  IF v_alert_count >= 10 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_levels IS NOT NULL THEN
    IF array_length(p_levels, 1) IS NULL THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    FOREACH v_level IN ARRAY p_levels LOOP
      IF NOT (v_level = ANY(v_allowed_levels)) THEN
        RAISE EXCEPTION 'Operation not permitted';
      END IF;
    END LOOP;
  END IF;

  IF p_starts_on IS NOT NULL AND p_ends_on IS NOT NULL AND p_ends_on < p_starts_on THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_ends_on IS NOT NULL AND p_ends_on < current_date THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  INSERT INTO activity_alerts (user_id, sport_key, location, radius_km, levels, starts_on, ends_on, created_at)
  VALUES (
    v_user_id,
    p_sport_key,
    ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
    p_radius_km,
    p_levels,
    p_starts_on,
    p_ends_on,
    now()
  )
  RETURNING id INTO v_alert_id;

  RETURN v_alert_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_alert FROM anon;
GRANT EXECUTE ON FUNCTION create_alert TO authenticated;
