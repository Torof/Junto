-- Migration 00141: offline geo replay + QR window extension to T+3h.
--
-- Outdoor activities (alpinism, ski touring) often start in remote zones
-- with no cell coverage. A participant who is offline from before meetup
-- through to ~1h after activity end currently has no way to validate
-- their presence: live geo/QR RPCs fail, peers can vote them in but only
-- if peers are confirmed themselves and 24h-window-active.
--
-- This migration adds two recovery paths:
--
--   1. confirm_presence_via_geo accepts an optional p_captured_at
--      timestamp. When provided, the function uses it for the
--      window check instead of now() — so a client can replay a
--      cached offline-captured geo event after reconnecting.
--      Bounds:
--        - Replay must arrive ≤ T+3h after activity end.
--        - p_captured_at must fall in the live geo window
--          (T-10min ≤ captured ≤ T+30min, matches mig 00131).
--        - All other gates unchanged: distance ≤ 150m, single-shot
--          flip, auth/suspension/accepted-participant.
--
--   2. confirm_presence_via_token's late window grows from
--      T+1h to T+3h after activity end. Cheap, low-risk: the
--      creator's QR is required anyway (live token).
--
-- Spoofing acknowledgement: a client can fabricate p_captured_at + lng/lat
-- without ever being there, since we don't sign these envelopes. The
-- bounds (window + distance + single-shot + accepted-only) raise the
-- floor; the social check is peer-review reputation badges
-- (level_overestimated, unreliable_field). A signed-token approach is
-- left for later if abuse becomes visible.

-- ============================================================================
-- 1. confirm_presence_via_geo — accept optional captured_at for offline replay
-- ============================================================================
CREATE OR REPLACE FUNCTION confirm_presence_via_geo(
  p_activity_id UUID,
  p_lng FLOAT,
  p_lat FLOAT,
  p_captured_at TIMESTAMPTZ DEFAULT NULL
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
  v_starts_at TIMESTAMPTZ;
  v_duration INTERVAL;
  v_window_anchor TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT starts_at, duration INTO v_starts_at, v_duration
  FROM activities WHERE id = p_activity_id;
  IF v_starts_at IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF p_captured_at IS NULL THEN
    -- Live path: now() must be in the geo window.
    v_window_anchor := now();
  ELSE
    -- Replay path: the replay itself must arrive within T+3h after end,
    -- and the captured timestamp must fall in the original geo window.
    IF now() > v_starts_at + v_duration + INTERVAL '3 hours' THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    v_window_anchor := p_captured_at;
  END IF;

  IF v_window_anchor < v_starts_at - INTERVAL '10 minutes'
     OR v_window_anchor > v_starts_at + INTERVAL '30 minutes' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, confirmed_present IS NOT NULL
  INTO v_participation_id, v_already_confirmed
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';

  IF v_participation_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_already_confirmed THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

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

  UPDATE participations SET confirmed_present = TRUE WHERE id = v_participation_id;
  PERFORM recalculate_reliability_score(v_user_id);
  PERFORM notify_presence_confirmed(v_user_id, p_activity_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION confirm_presence_via_geo(UUID, FLOAT, FLOAT, TIMESTAMPTZ) FROM anon;
GRANT EXECUTE ON FUNCTION confirm_presence_via_geo(UUID, FLOAT, FLOAT, TIMESTAMPTZ) TO authenticated;

-- ============================================================================
-- 2. confirm_presence_via_token — extend post-end window from 1h to 3h
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
  v_creator_id UUID;
  v_creator_flipped INTEGER;
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

  SELECT starts_at, duration, creator_id INTO v_starts_at, v_duration, v_creator_id
  FROM activities WHERE id = v_activity_id;
  IF v_starts_at IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF now() < v_starts_at - INTERVAL '30 minutes' OR now() > v_starts_at + v_duration + INTERVAL '3 hours' THEN
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
  PERFORM notify_presence_confirmed(v_user_id, v_activity_id);

  IF v_creator_id IS NOT NULL AND v_creator_id != v_user_id THEN
    UPDATE participations
    SET confirmed_present = TRUE
    WHERE activity_id = v_activity_id
      AND user_id = v_creator_id
      AND status = 'accepted'
      AND confirmed_present IS NULL;
    GET DIAGNOSTICS v_creator_flipped = ROW_COUNT;
    IF v_creator_flipped > 0 THEN
      PERFORM recalculate_reliability_score(v_creator_id);
      PERFORM notify_presence_confirmed(v_creator_id, v_activity_id);
    END IF;
  END IF;

  RETURN v_activity_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION confirm_presence_via_token FROM anon;
GRANT EXECUTE ON FUNCTION confirm_presence_via_token TO authenticated;
