-- Migration 00063: fix new presence RPCs — confirmed_present is BOOLEAN, not TIMESTAMPTZ.

CREATE OR REPLACE FUNCTION confirm_presence_via_geo(
  p_activity_id UUID,
  p_lng FLOAT,
  p_lat FLOAT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_user_point GEOGRAPHY;
  v_d_start FLOAT;
  v_d_meeting FLOAT;
  v_d_end FLOAT;
  v_min_distance FLOAT;
  v_participation_id UUID;
  v_already_confirmed BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT _is_presence_window(p_activity_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, confirmed_present IS NOT NULL
  INTO v_participation_id, v_already_confirmed
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';

  IF v_participation_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_already_confirmed THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_user_point := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography;

  SELECT
    ST_Distance(location_start, v_user_point),
    CASE WHEN location_meeting IS NOT NULL THEN ST_Distance(location_meeting, v_user_point) ELSE NULL END,
    CASE WHEN location_end IS NOT NULL THEN ST_Distance(location_end, v_user_point) ELSE NULL END
  INTO v_d_start, v_d_meeting, v_d_end
  FROM activities WHERE id = p_activity_id;

  v_min_distance := LEAST(
    coalesce(v_d_start, 999999),
    coalesce(v_d_meeting, 999999),
    coalesce(v_d_end, 999999)
  );

  IF v_min_distance IS NULL OR v_min_distance > 150 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE participations
  SET confirmed_present = TRUE
  WHERE id = v_participation_id;

  PERFORM recalculate_reliability_score(v_user_id);
END;
$$;

CREATE OR REPLACE FUNCTION create_presence_token(p_activity_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_creator_id UUID;
  v_token TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT creator_id INTO v_creator_id FROM activities WHERE id = p_activity_id;
  IF v_creator_id IS NULL OR v_creator_id != v_user_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT _is_presence_window(p_activity_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT token INTO v_token
  FROM presence_tokens
  WHERE activity_id = p_activity_id AND expires_at > now()
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_token IS NULL THEN
    v_token := replace(gen_random_uuid()::text, '-', '');
    INSERT INTO presence_tokens (token, activity_id, expires_at)
    VALUES (v_token, p_activity_id, now() + INTERVAL '30 minutes');
  END IF;

  UPDATE participations
  SET confirmed_present = TRUE
  WHERE activity_id = p_activity_id AND user_id = v_user_id
    AND status = 'accepted' AND confirmed_present IS NULL;

  RETURN v_token;
END;
$$;

CREATE OR REPLACE FUNCTION confirm_presence_via_token(p_token TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_activity_id UUID;
  v_expires_at TIMESTAMPTZ;
  v_participation_id UUID;
  v_already_confirmed BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT activity_id, expires_at INTO v_activity_id, v_expires_at
  FROM presence_tokens WHERE token = p_token;

  IF v_activity_id IS NULL OR v_expires_at < now() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, confirmed_present IS NOT NULL
  INTO v_participation_id, v_already_confirmed
  FROM participations
  WHERE activity_id = v_activity_id AND user_id = v_user_id AND status = 'accepted';

  IF v_participation_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_already_confirmed THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE participations
  SET confirmed_present = TRUE
  WHERE id = v_participation_id;

  PERFORM recalculate_reliability_score(v_user_id);

  RETURN v_activity_id;
END;
$$;

CREATE OR REPLACE FUNCTION creator_override_presence(
  p_activity_id UUID,
  p_present_user_ids UUID[]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_creator_id UUID;
  v_target_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT creator_id INTO v_creator_id FROM activities WHERE id = p_activity_id;
  IF v_creator_id IS NULL OR v_creator_id != v_user_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT _is_presence_window(p_activity_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  FOREACH v_target_id IN ARRAY p_present_user_ids LOOP
    UPDATE participations
    SET confirmed_present = TRUE
    WHERE activity_id = p_activity_id
      AND user_id = v_target_id
      AND status = 'accepted'
      AND confirmed_present IS NULL;

    PERFORM recalculate_reliability_score(v_target_id);
  END LOOP;
END;
$$;
