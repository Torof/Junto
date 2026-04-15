-- Migration 00065: cancellation flow with reasons + late-cancel penalty waiver

-- ============================================================================
-- Schema
-- ============================================================================
ALTER TABLE participations ADD COLUMN left_reason TEXT;
ALTER TABLE participations ADD COLUMN penalty_waived BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE activities ADD COLUMN cancelled_reason TEXT;

-- Whitelist: penalty_waived is privileged (waivable only via RPC), left_reason is set on leave RPC only
-- The whitelist trigger on participations doesn't exist — these are only writable via SECURITY DEFINER fns

-- ============================================================================
-- leave_activity — accept optional reason, notify creator, mark late if applicable
-- ============================================================================
DROP FUNCTION IF EXISTS leave_activity(UUID);

CREATE OR REPLACE FUNCTION leave_activity(
  p_activity_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_participation RECORD;
  v_activity RECORD;
  v_user_name TEXT;
  v_is_late BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT p.id, p.status
  INTO v_participation
  FROM participations p
  WHERE p.activity_id = p_activity_id AND p.user_id = v_user_id
  FOR UPDATE;

  IF v_participation IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_participation.status NOT IN ('accepted', 'pending') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, status, starts_at, creator_id, title INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_is_late := v_activity.starts_at - INTERVAL '12 hours' < now();

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET status = 'withdrawn',
      left_at = now(),
      left_reason = NULLIF(trim(coalesce(p_reason, '')), '')
  WHERE id = v_participation.id;

  PERFORM recalculate_reliability_score(v_user_id);

  -- Notify creator (in-app + push via existing trigger on notifications)
  SELECT display_name INTO v_user_name FROM users WHERE id = v_user_id;
  PERFORM create_notification(
    v_activity.creator_id,
    CASE WHEN v_is_late THEN 'participant_left_late' ELSE 'participant_left' END,
    coalesce(v_user_name, 'Quelqu''un') || ' a quitté l''activité',
    CASE
      WHEN v_is_late AND p_reason IS NOT NULL AND trim(p_reason) != '' THEN trim(p_reason) || ' · Pénalité appliquée'
      WHEN v_is_late THEN 'Pénalité de fiabilité appliquée — tu peux la lever'
      WHEN p_reason IS NOT NULL AND trim(p_reason) != '' THEN trim(p_reason)
      ELSE v_activity.title
    END,
    jsonb_build_object('activity_id', p_activity_id, 'participation_id', v_participation.id, 'late', v_is_late)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION leave_activity FROM anon;
GRANT EXECUTE ON FUNCTION leave_activity TO authenticated;

-- ============================================================================
-- cancel_activity — require reason, notify all accepted participants
-- ============================================================================
DROP FUNCTION IF EXISTS cancel_activity(UUID);

CREATE OR REPLACE FUNCTION cancel_activity(
  p_activity_id UUID,
  p_reason TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_participant RECORD;
  v_clean_reason TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_reason := NULLIF(trim(coalesce(p_reason, '')), '');
  IF v_clean_reason IS NULL OR char_length(v_clean_reason) < 3 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, creator_id, status, title
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id
  FOR UPDATE;

  IF v_activity IS NULL OR v_user_id != v_activity.creator_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE activities
  SET status = 'cancelled',
      cancelled_reason = v_clean_reason,
      updated_at = now()
  WHERE id = p_activity_id;

  -- Notify all accepted participants except creator
  FOR v_participant IN
    SELECT user_id FROM participations
    WHERE activity_id = p_activity_id
      AND status IN ('accepted', 'pending')
      AND user_id != v_user_id
  LOOP
    PERFORM create_notification(
      v_participant.user_id,
      'activity_cancelled',
      'Activité annulée — ' || v_activity.title,
      v_clean_reason,
      jsonb_build_object('activity_id', p_activity_id)
    );
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION cancel_activity FROM anon;
GRANT EXECUTE ON FUNCTION cancel_activity TO authenticated;

-- ============================================================================
-- waive_late_cancel_penalty — creator only, lifts the late-cancel penalty
-- ============================================================================
CREATE OR REPLACE FUNCTION waive_late_cancel_penalty(p_participation_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_participation RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT p.id, p.user_id, p.status, p.left_at, p.penalty_waived, a.creator_id, a.starts_at
  INTO v_participation
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.id = p_participation_id;

  IF v_participation IS NULL OR v_user_id != v_participation.creator_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_participation.status != 'withdrawn' OR v_participation.left_at IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Only late cancels can be waived (>12h leaves had no penalty to begin with)
  IF v_participation.left_at <= v_participation.starts_at - INTERVAL '12 hours' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_participation.penalty_waived THEN
    RETURN; -- idempotent
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations SET penalty_waived = TRUE WHERE id = p_participation_id;

  PERFORM recalculate_reliability_score(v_participation.user_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION waive_late_cancel_penalty FROM anon;
GRANT EXECUTE ON FUNCTION waive_late_cancel_penalty TO authenticated;

-- ============================================================================
-- recalculate_reliability_score — honor penalty_waived
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
  v_total INTEGER;
  v_present INTEGER;
  v_late_cancels INTEGER;
  v_score FLOAT;
BEGIN
  SELECT count(*) INTO v_total
  FROM participations
  WHERE user_id = p_user_id
    AND confirmed_present IS NOT NULL;

  SELECT count(*) INTO v_present
  FROM participations
  WHERE user_id = p_user_id
    AND confirmed_present = true;

  SELECT count(*) INTO v_late_cancels
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.user_id = p_user_id
    AND p.status = 'withdrawn'
    AND p.left_at IS NOT NULL
    AND p.left_at > a.starts_at - INTERVAL '12 hours'
    AND p.penalty_waived = FALSE;

  IF v_total + v_late_cancels = 0 THEN
    v_score := NULL;
  ELSE
    v_score := ROUND(((v_present::float / (v_total + v_late_cancels)::float) * 100)::numeric, 1)::float;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET reliability_score = v_score WHERE id = p_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION recalculate_reliability_score FROM anon, authenticated;
