-- Migration 00048: Multi-level + time-bounded activity alerts

-- ============================================================================
-- Schema changes
-- ============================================================================

-- Replace single `level` with `levels` array
ALTER TABLE activity_alerts ADD COLUMN levels TEXT[];
UPDATE activity_alerts SET levels = ARRAY[level] WHERE level IS NOT NULL;
ALTER TABLE activity_alerts DROP COLUMN level;

-- Time window (both nullable = always active)
ALTER TABLE activity_alerts ADD COLUMN starts_on DATE;
ALTER TABLE activity_alerts ADD COLUMN ends_on DATE;
ALTER TABLE activity_alerts ADD CONSTRAINT alerts_period_valid
  CHECK (ends_on IS NULL OR starts_on IS NULL OR ends_on >= starts_on);

-- Validate levels contents if provided
ALTER TABLE activity_alerts ADD CONSTRAINT alerts_levels_nonempty
  CHECK (levels IS NULL OR array_length(levels, 1) > 0);

-- ============================================================================
-- Replace create_alert
-- ============================================================================
DROP FUNCTION IF EXISTS create_alert(FLOAT, FLOAT, INTEGER, TEXT, TEXT);

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
  v_allowed_levels TEXT[] := ARRAY['beginner', 'intermediate', 'advanced', 'expert'];
  v_level TEXT;
BEGIN
  -- 1. Auth check
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 2. Suspension check
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 3. Premium check
  SELECT tier INTO v_tier FROM users WHERE id = v_user_id;
  IF v_tier NOT IN ('premium', 'pro') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 4. Max 10 alerts per user
  SELECT count(*) INTO v_alert_count FROM activity_alerts WHERE user_id = v_user_id;
  IF v_alert_count >= 10 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 5. Levels validation
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

  -- 6. Period validation
  IF p_starts_on IS NOT NULL AND p_ends_on IS NOT NULL AND p_ends_on < p_starts_on THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_ends_on IS NOT NULL AND p_ends_on < current_date THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 7. Insert
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

-- ============================================================================
-- Update check_alerts_for_activity: multi-level + period matching
-- ============================================================================
CREATE OR REPLACE FUNCTION check_alerts_for_activity(
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_activity RECORD;
  v_alert RECORD;
  v_sport_key TEXT;
  v_activity_date DATE;
BEGIN
  SELECT id, title, sport_id, location_start, location_meeting, level, creator_id, starts_at
  INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;

  SELECT key INTO v_sport_key FROM sports WHERE id = v_activity.sport_id;
  v_activity_date := v_activity.starts_at::date;

  FOR v_alert IN
    SELECT a.id, a.user_id
    FROM activity_alerts a
    WHERE a.user_id != v_activity.creator_id
      AND (a.sport_key IS NULL OR a.sport_key = v_sport_key)
      AND (a.levels IS NULL OR v_activity.level = ANY(a.levels))
      AND (a.starts_on IS NULL OR v_activity_date >= a.starts_on)
      AND (a.ends_on IS NULL OR v_activity_date <= a.ends_on)
      AND (
        ST_DWithin(a.location, v_activity.location_start, a.radius_km * 1000)
        OR (v_activity.location_meeting IS NOT NULL
            AND ST_DWithin(a.location, v_activity.location_meeting, a.radius_km * 1000))
      )
  LOOP
    PERFORM create_notification(
      v_alert.user_id,
      'alert_match',
      'Nouvelle activité',
      v_activity.title || ' correspond à ton alerte',
      jsonb_build_object('activity_id', p_activity_id)
    );
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION check_alerts_for_activity FROM anon, authenticated;
