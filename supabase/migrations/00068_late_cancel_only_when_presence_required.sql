-- Migration 00068: late-cancel penalty only counts when the activity required presence verification.
-- Symmetric with the per-activity toggle: if the creator didn't require presence,
-- leaving late doesn't damage the participant's reliability score either.

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
    AND p.penalty_waived = FALSE
    AND a.requires_presence = TRUE;

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

-- Also: leave_activity's "late" flag now only fires if the activity requires presence.
-- Notification + creator-side waive UI both rely on it being true.
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
  v_reason TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_reason := NULLIF(left(trim(coalesce(p_reason, '')), 200), '');

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

  SELECT id, status, starts_at, creator_id, title, requires_presence INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_is_late := v_activity.requires_presence
               AND (v_activity.starts_at - INTERVAL '12 hours' < now());

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET status = 'withdrawn',
      left_at = now(),
      left_reason = v_reason
  WHERE id = v_participation.id;

  PERFORM recalculate_reliability_score(v_user_id);

  SELECT display_name INTO v_user_name FROM users WHERE id = v_user_id;
  PERFORM create_notification(
    v_activity.creator_id,
    CASE WHEN v_is_late THEN 'participant_left_late' ELSE 'participant_left' END,
    coalesce(v_user_name, 'Quelqu''un') || ' a quitté l''activité',
    CASE
      WHEN v_is_late AND v_reason IS NOT NULL THEN v_reason || ' · Pénalité appliquée'
      WHEN v_is_late THEN 'Pénalité de fiabilité appliquée — tu peux la lever'
      WHEN v_reason IS NOT NULL THEN v_reason
      ELSE v_activity.title
    END,
    jsonb_build_object('activity_id', p_activity_id, 'participation_id', v_participation.id, 'late', v_is_late)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION leave_activity FROM anon;
GRANT EXECUTE ON FUNCTION leave_activity TO authenticated;
