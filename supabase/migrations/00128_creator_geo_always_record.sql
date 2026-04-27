-- Migration 00128: creator can always geo-self-validate; reliability ignores
-- the row until a second accepted participant exists.
--
-- 00126 made the creator's geo-self-validation conditional on having at
-- least one other accepted participant — server rejected solo creators.
-- New design: always accept the validation (the act of pressing geo from
-- inside the zone is a useful event), but recalculate_reliability_score
-- excludes rows where the user IS the activity creator AND no other
-- accepted participant exists. If someone joins later, the next recalc
-- starts counting it automatically.

-- ============================================================================
-- 1. confirm_presence_via_geo: drop the creator-alone check
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
  v_user_point GEOGRAPHY;
  v_d_start FLOAT;
  v_d_meeting FLOAT;
  v_d_end FLOAT;
  v_min_distance FLOAT;
  v_participation_id UUID;
  v_already_confirmed BOOLEAN;
  v_starts_at TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT starts_at INTO v_starts_at
  FROM activities WHERE id = p_activity_id;
  IF v_starts_at IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF now() < v_starts_at - INTERVAL '10 minutes' OR now() > v_starts_at + INTERVAL '30 minutes' THEN
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
END;
$$;

REVOKE EXECUTE ON FUNCTION confirm_presence_via_geo FROM anon;
GRANT EXECUTE ON FUNCTION confirm_presence_via_geo TO authenticated;

-- ============================================================================
-- 2. recalculate_reliability_score: ignore solo-creator validations
-- ============================================================================
CREATE OR REPLACE FUNCTION recalculate_reliability_score(
  p_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prior CONSTANT INTEGER := 3;
  v_total INTEGER;
  v_present INTEGER;
  v_late_cancels INTEGER;
  v_score FLOAT;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('reliability_' || p_user_id::text));

  -- Validations on activities where the user is the creator AND no other
  -- accepted participant exists are recorded but don't count toward
  -- reliability — solo activities can't be peer-witnessed. The next recalc
  -- after a participant joins picks them up automatically.
  SELECT count(*) INTO v_total
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.user_id = p_user_id
    AND p.confirmed_present IS NOT NULL
    AND NOT (
      p.user_id = a.creator_id
      AND NOT EXISTS (
        SELECT 1 FROM participations p2
        WHERE p2.activity_id = p.activity_id
          AND p2.user_id != p.user_id
          AND p2.status = 'accepted'
      )
    );

  SELECT count(*) INTO v_present
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.user_id = p_user_id
    AND p.confirmed_present = true
    AND NOT (
      p.user_id = a.creator_id
      AND NOT EXISTS (
        SELECT 1 FROM participations p2
        WHERE p2.activity_id = p.activity_id
          AND p2.user_id != p.user_id
          AND p2.status = 'accepted'
      )
    );

  SELECT count(*) INTO v_late_cancels
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.user_id = p_user_id
    AND p.status = 'withdrawn'
    AND p.left_at IS NOT NULL
    AND p.left_at > a.starts_at - INTERVAL '12 hours'
    AND p.penalty_waived = FALSE
    AND a.requires_presence = TRUE;

  v_score := ROUND(
    (((v_prior + v_present)::float / (v_prior + v_total + v_late_cancels)::float) * 100)::numeric,
    1
  )::float;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET reliability_score = v_score WHERE id = p_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION recalculate_reliability_score FROM anon, authenticated;

-- ============================================================================
-- 3. Trigger recalc when accepted participant count crosses 1↔2 boundary,
--    so a solo creator's recorded validation starts counting once someone
--    joins (and stops counting if they all leave).
-- ============================================================================
CREATE OR REPLACE FUNCTION recalc_creator_on_participant_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_creator_id UUID;
  v_other_count INTEGER;
BEGIN
  SELECT creator_id INTO v_creator_id
  FROM activities WHERE id = COALESCE(NEW.activity_id, OLD.activity_id);
  IF v_creator_id IS NULL THEN RETURN COALESCE(NEW, OLD); END IF;

  -- If the creator hasn't recorded a presence on this activity, nothing to do.
  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = COALESCE(NEW.activity_id, OLD.activity_id)
      AND user_id = v_creator_id
      AND confirmed_present IS NOT NULL
  ) THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Recalc the creator's score so the recorded validation flips to counted
  -- (or back to ignored) based on the new participant pool.
  PERFORM recalculate_reliability_score(v_creator_id);
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_recalc_creator_on_participant_change ON participations;
CREATE TRIGGER trg_recalc_creator_on_participant_change
  AFTER INSERT OR UPDATE OF status ON participations
  FOR EACH ROW
  EXECUTE FUNCTION recalc_creator_on_participant_change();
