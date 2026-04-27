-- Migration 00124: extend QR validation window to T-30min.
-- The presence_pre_warning notif fires at T-30min ("starts in 30 min, get
-- ready to validate"), but the QR window opened at T-10min — so users (and
-- creators trying to generate the code) tapped the button and got a generic
-- error 20 minutes before anything could happen.
--
-- Geo window stays at T-10min: it's location-only, so opening it earlier
-- would let people validate from the parking lot half an hour out. QR is
-- gated by the creator showing the code in person, so the timestamp matters
-- less — extending it to match the notif lead time.

-- ============================================================================
-- 1. confirm_presence_via_token: T-30min → T+duration+1h
-- ============================================================================
CREATE OR REPLACE FUNCTION confirm_presence_via_token(
  p_token TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_token_record RECORD;
  v_participation_id UUID;
  v_already_confirmed BOOLEAN;
  v_activity_id UUID;
  v_starts_at TIMESTAMPTZ;
  v_duration INTERVAL;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT activity_id, expires_at INTO v_token_record
  FROM presence_tokens WHERE token = p_token;
  IF v_token_record IS NULL OR v_token_record.expires_at < now() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_activity_id := v_token_record.activity_id;

  SELECT starts_at, duration INTO v_starts_at, v_duration
  FROM activities WHERE id = v_activity_id;
  IF v_starts_at IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF now() < v_starts_at - INTERVAL '30 minutes' OR now() > v_starts_at + v_duration + INTERVAL '1 hour' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, confirmed_present IS NOT NULL
  INTO v_participation_id, v_already_confirmed
  FROM participations
  WHERE activity_id = v_activity_id AND user_id = v_user_id AND status = 'accepted';

  IF v_participation_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_already_confirmed THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  UPDATE participations SET confirmed_present = TRUE WHERE id = v_participation_id;
  PERFORM recalculate_reliability_score(v_user_id);

  RETURN v_activity_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION confirm_presence_via_token FROM anon;
GRANT EXECUTE ON FUNCTION confirm_presence_via_token TO authenticated;

-- ============================================================================
-- 2. create_presence_token: T-30min → T+duration+1h
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
  v_starts_at TIMESTAMPTZ;
  v_duration INTERVAL;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT creator_id, starts_at, duration INTO v_creator_id, v_starts_at, v_duration
  FROM activities WHERE id = p_activity_id;
  IF v_creator_id IS NULL OR v_creator_id != v_user_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF now() < v_starts_at - INTERVAL '30 minutes' OR now() > v_starts_at + v_duration + INTERVAL '1 hour' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Reuse a non-expired token if one exists (prevents creator from spawning many)
  SELECT token INTO v_token FROM presence_tokens
  WHERE activity_id = p_activity_id AND expires_at > now()
  LIMIT 1;

  IF v_token IS NULL THEN
    v_token := substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
    INSERT INTO presence_tokens (token, activity_id, expires_at)
    VALUES (v_token, p_activity_id, now() + INTERVAL '30 minutes');
  END IF;

  RETURN v_token;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_presence_token FROM anon;
GRANT EXECUTE ON FUNCTION create_presence_token TO authenticated;
