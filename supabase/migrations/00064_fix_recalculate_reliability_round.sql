-- Migration 00064: fix recalculate_reliability_score
-- ROUND(double precision, int) doesn't exist in Postgres — cast to numeric.

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
    AND p.left_at > a.starts_at - INTERVAL '12 hours';

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
