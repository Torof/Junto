-- Migration 00059: presence confirmation v2 — geo self check-in + QR token + creator override

-- ============================================================================
-- TABLE: presence_tokens (short-lived, creator-generated, scannable)
-- ============================================================================
CREATE TABLE presence_tokens (
  token TEXT PRIMARY KEY,
  activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE INDEX idx_presence_tokens_activity ON presence_tokens(activity_id);

ALTER TABLE presence_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE presence_tokens FORCE ROW LEVEL SECURITY;
-- No client CRUD; only via SECURITY DEFINER functions.

-- ============================================================================
-- Helper: is the activity currently in its presence window
-- Window: starts_at - 2h  ..  starts_at + duration + 12h
-- ============================================================================
CREATE OR REPLACE FUNCTION _is_presence_window(p_activity_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_starts_at TIMESTAMPTZ;
  v_duration INTERVAL;
BEGIN
  SELECT starts_at, duration INTO v_starts_at, v_duration
  FROM activities WHERE id = p_activity_id;

  IF v_starts_at IS NULL THEN RETURN FALSE; END IF;

  RETURN now() BETWEEN (v_starts_at - INTERVAL '2 hours')
                   AND (v_starts_at + v_duration + INTERVAL '12 hours');
END;
$$;

REVOKE EXECUTE ON FUNCTION _is_presence_window FROM anon, authenticated;

-- ============================================================================
-- FUNCTION: confirm_presence_via_geo (participant self check-in)
-- ============================================================================
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
  v_distance FLOAT;
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

  -- Must be an accepted participant, not already confirmed
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

  -- Distance check: within 150m of location_start
  SELECT ST_Distance(
    location_start,
    ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
  ) INTO v_distance
  FROM activities WHERE id = p_activity_id;

  IF v_distance IS NULL OR v_distance > 150 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE participations
  SET confirmed_present = now()
  WHERE id = v_participation_id;

  PERFORM recalculate_reliability_score(v_user_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION confirm_presence_via_geo FROM anon;
GRANT EXECUTE ON FUNCTION confirm_presence_via_geo TO authenticated;

-- ============================================================================
-- FUNCTION: create_presence_token (creator generates a QR token)
-- Token lives 30 min. Auto-confirms the creator.
-- ============================================================================
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

  -- Reuse an active token if one exists
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

  -- Auto-confirm the creator if not yet
  UPDATE participations
  SET confirmed_present = now()
  WHERE activity_id = p_activity_id AND user_id = v_user_id
    AND status = 'accepted' AND confirmed_present IS NULL;

  RETURN v_token;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_presence_token FROM anon;
GRANT EXECUTE ON FUNCTION create_presence_token TO authenticated;

-- ============================================================================
-- FUNCTION: confirm_presence_via_token (participant scans QR)
-- ============================================================================
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
  SET confirmed_present = now()
  WHERE id = v_participation_id;

  PERFORM recalculate_reliability_score(v_user_id);

  RETURN v_activity_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION confirm_presence_via_token FROM anon;
GRANT EXECUTE ON FUNCTION confirm_presence_via_token TO authenticated;

-- ============================================================================
-- FUNCTION: creator_override_presence (escape hatch — creator marks manually)
-- Replaces the old confirm_presence behaviour (which required status=completed).
-- Now works inside the broader presence window.
-- ============================================================================
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
    SET confirmed_present = now()
    WHERE activity_id = p_activity_id
      AND user_id = v_target_id
      AND status = 'accepted'
      AND confirmed_present IS NULL;

    PERFORM recalculate_reliability_score(v_target_id);
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION creator_override_presence FROM anon;
GRANT EXECUTE ON FUNCTION creator_override_presence TO authenticated;
