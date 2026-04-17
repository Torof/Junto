-- Migration 00070: Bayesian reliability score
-- Replaces the raw ratio with a Bayesian average that includes 3
-- "virtual positive" activities as a prior. New users start at 100%
-- instead of NULL. One miss drops to 75% (survivable) not 0% (death
-- spiral). After ~10 real activities the prior's influence fades to
-- negligible and real behavior dominates.
--
-- Formula: score = ((PRIOR × 100) + (present × 100)) / (PRIOR + total + late_cancels)
-- Where PRIOR = 3 virtual positive activities.

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
  -- Activities where presence was explicitly checked (true or false)
  SELECT count(*) INTO v_total
  FROM participations
  WHERE user_id = p_user_id
    AND confirmed_present IS NOT NULL;

  -- Activities where user was confirmed present
  SELECT count(*) INTO v_present
  FROM participations
  WHERE user_id = p_user_id
    AND confirmed_present = true;

  -- Late cancellations (withdrawn <12h before start, not waived, presence required)
  SELECT count(*) INTO v_late_cancels
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.user_id = p_user_id
    AND p.status = 'withdrawn'
    AND p.left_at IS NOT NULL
    AND p.left_at > a.starts_at - INTERVAL '12 hours'
    AND p.penalty_waived = FALSE
    AND a.requires_presence = TRUE;

  -- Bayesian average: prior of 3 virtual positive activities
  -- Denominator is never 0 because v_prior = 3
  v_score := ROUND(
    (((v_prior + v_present)::float / (v_prior + v_total + v_late_cancels)::float) * 100)::numeric,
    1
  )::float;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET reliability_score = v_score WHERE id = p_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION recalculate_reliability_score FROM anon, authenticated;

-- Backfill: recalculate all existing users so nobody is stuck at NULL
DO $$
DECLARE
  v_user RECORD;
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  FOR v_user IN SELECT id FROM users LOOP
    PERFORM recalculate_reliability_score(v_user.id);
  END LOOP;
END $$;
