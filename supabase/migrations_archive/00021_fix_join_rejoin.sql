-- Migration 00021: fix join_activity to handle re-joining after withdrawal
-- Also fix participations RLS (remove recursive co-participant check)

-- Fix RLS (should already be done via SQL Editor, but ensure migration matches)
DROP POLICY IF EXISTS "participations_select" ON participations;
DROP POLICY IF EXISTS "participations_select_own" ON participations;

CREATE POLICY "participations_select_own"
  ON participations FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- Recreate join_activity with re-join support
DROP FUNCTION IF EXISTS join_activity;

CREATE OR REPLACE FUNCTION join_activity(
  p_activity_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_current_count INTEGER;
  v_hourly_count INTEGER;
  v_result_status TEXT;
  v_existing RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, creator_id, status, visibility, max_participants
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id
  FOR UPDATE;

  IF v_activity IS NULL OR v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = v_activity.creator_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = v_activity.creator_id AND blocked_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT count(*) INTO v_current_count
  FROM participations
  WHERE activity_id = p_activity_id AND status = 'accepted';

  IF v_current_count >= v_activity.max_participants THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT count(*) INTO v_hourly_count
  FROM participations
  WHERE user_id = v_user_id AND created_at > NOW() - INTERVAL '1 hour';

  IF v_hourly_count >= 100 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_activity.visibility IN ('public', 'private_link') THEN
    v_result_status := 'accepted';
  ELSE
    v_result_status := 'pending';
  END IF;

  -- Check for existing participation (withdrawn or refused — allow re-join)
  SELECT id, status INTO v_existing
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id;

  IF v_existing IS NOT NULL THEN
    -- Can re-join if withdrawn or refused, NOT if removed
    IF v_existing.status = 'removed' THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;

    IF v_existing.status IN ('accepted', 'pending') THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;

    -- Re-join: update existing row
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE participations
    SET status = v_result_status, left_at = NULL, created_at = now()
    WHERE id = v_existing.id;
  ELSE
    -- New join
    INSERT INTO participations (activity_id, user_id, status, created_at)
    VALUES (p_activity_id, v_user_id, v_result_status, now());
  END IF;

  RETURN v_result_status;
END;
$$;

REVOKE EXECUTE ON FUNCTION join_activity FROM public;
GRANT EXECUTE ON FUNCTION join_activity TO authenticated;
