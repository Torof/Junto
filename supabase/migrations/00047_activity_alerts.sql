-- Migration 00047: Personalized activity alerts (Premium feature)

-- ============================================================================
-- TABLE: activity_alerts
-- ============================================================================
CREATE TABLE activity_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sport_key TEXT,
  location GEOGRAPHY(Point, 4326) NOT NULL,
  radius_km INTEGER NOT NULL CHECK (radius_km BETWEEN 5 AND 200),
  level TEXT,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE INDEX idx_activity_alerts_user ON activity_alerts(user_id);
CREATE INDEX idx_activity_alerts_location ON activity_alerts USING GIST (location);

ALTER TABLE activity_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity_alerts FORCE ROW LEVEL SECURITY;

-- SELECT/DELETE: own alerts only
CREATE POLICY "alerts_select_own"
  ON activity_alerts FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "alerts_delete_own"
  ON activity_alerts FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- INSERT/UPDATE: via function only

-- ============================================================================
-- FUNCTION: create_alert (Premium only, max 10 per user)
-- ============================================================================
CREATE OR REPLACE FUNCTION create_alert(
  p_lng FLOAT,
  p_lat FLOAT,
  p_radius_km INTEGER,
  p_sport_key TEXT DEFAULT NULL,
  p_level TEXT DEFAULT NULL
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

  -- 5. Insert alert
  INSERT INTO activity_alerts (user_id, sport_key, location, radius_km, level, created_at)
  VALUES (
    v_user_id,
    p_sport_key,
    ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
    p_radius_km,
    p_level,
    now()
  )
  RETURNING id INTO v_alert_id;

  RETURN v_alert_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_alert FROM anon;
GRANT EXECUTE ON FUNCTION create_alert TO authenticated;

-- ============================================================================
-- FUNCTION: check_alerts (internal — called after activity creation)
-- Matches new activity against all alerts and sends notifications
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
BEGIN
  -- Get activity details
  SELECT id, title, sport_id, location_start, location_meeting, level, creator_id
  INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;

  -- Get sport key
  SELECT key INTO v_sport_key FROM sports WHERE id = v_activity.sport_id;

  -- Match against alerts (check both start and meeting locations)
  FOR v_alert IN
    SELECT a.id, a.user_id
    FROM activity_alerts a
    WHERE a.user_id != v_activity.creator_id
      AND (a.sport_key IS NULL OR a.sport_key = v_sport_key)
      AND (a.level IS NULL OR a.level = v_activity.level)
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

-- ============================================================================
-- Update create_activity to trigger alert check after creation
-- ============================================================================
CREATE OR REPLACE FUNCTION create_activity(
  p_sport_id UUID,
  p_title TEXT,
  p_description TEXT,
  p_level TEXT,
  p_max_participants INTEGER,
  p_start_lng FLOAT,
  p_start_lat FLOAT,
  p_meeting_lng FLOAT DEFAULT NULL,
  p_meeting_lat FLOAT DEFAULT NULL,
  p_end_lng FLOAT DEFAULT NULL,
  p_end_lat FLOAT DEFAULT NULL,
  p_starts_at TIMESTAMPTZ DEFAULT NULL,
  p_duration TEXT DEFAULT '2 hours',
  p_visibility TEXT DEFAULT 'public'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_tier TEXT;
  v_phone_verified BOOLEAN;
  v_monthly_count INTEGER;
  v_daily_count INTEGER;
  v_activity_id UUID;
  v_title TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_title := trim(p_title);
  IF char_length(v_title) < 3 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT phone_verified, tier INTO v_phone_verified, v_tier
  FROM users WHERE id = v_user_id;

  IF NOT v_phone_verified THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_visibility IN ('private_link', 'private_link_approval') AND v_tier = 'free' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_starts_at IS NULL OR p_starts_at <= NOW() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_create_activity'));

  SELECT count(*) INTO v_daily_count
  FROM activities
  WHERE creator_id = v_user_id AND created_at > NOW() - INTERVAL '1 day';

  IF v_daily_count >= 20 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_tier = 'free' THEN
    SELECT count(*) INTO v_monthly_count
    FROM activities
    WHERE creator_id = v_user_id AND created_at > NOW() - INTERVAL '1 month';

    IF v_monthly_count >= 4 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  INSERT INTO activities (
    creator_id, sport_id, title, description, level,
    max_participants, location_start, location_meeting, location_end,
    starts_at, duration, visibility, status, created_at, updated_at
  ) VALUES (
    v_user_id, p_sport_id, v_title, trim(p_description), p_level,
    p_max_participants,
    ST_SetSRID(ST_MakePoint(p_start_lng, p_start_lat), 4326)::geography,
    CASE WHEN p_meeting_lng IS NOT NULL AND p_meeting_lat IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_meeting_lng, p_meeting_lat), 4326)::geography
      ELSE NULL END,
    CASE WHEN p_end_lng IS NOT NULL AND p_end_lat IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_end_lng, p_end_lat), 4326)::geography
      ELSE NULL END,
    p_starts_at, p_duration::interval, p_visibility, 'published', now(), now()
  ) RETURNING id INTO v_activity_id;

  INSERT INTO participations (activity_id, user_id, status, created_at)
  VALUES (v_activity_id, v_user_id, 'accepted', now());

  -- Check alerts for matching users (only for public/approval activities)
  IF p_visibility IN ('public', 'approval') THEN
    PERFORM check_alerts_for_activity(v_activity_id);
  END IF;

  RETURN v_activity_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_activity FROM anon;
GRANT EXECUTE ON FUNCTION create_activity TO authenticated;
