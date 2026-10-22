-- Migration 00020: Sprint 4 — join, accept, refuse, leave, remove, cancel functions
-- + left_at column on participations

-- ============================================================================
-- SCHEMA: add left_at to participations
-- ============================================================================
ALTER TABLE participations ADD COLUMN left_at TIMESTAMPTZ;

-- ============================================================================
-- FUNCTION: join_activity
-- ============================================================================
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
BEGIN
  -- 1. Auth check
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 2. Suspension check
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 3. Activity status + lock row
  SELECT id, creator_id, status, visibility, max_participants
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id
  FOR UPDATE;

  IF v_activity IS NULL OR v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 4. Not the creator
  IF v_user_id = v_activity.creator_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 5. Not blocked by creator
  IF EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = v_activity.creator_id AND blocked_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 6. Seat count
  SELECT count(*) INTO v_current_count
  FROM participations
  WHERE activity_id = p_activity_id AND status = 'accepted';

  IF v_current_count >= v_activity.max_participants THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 7. Rate limit (10/hour)
  SELECT count(*) INTO v_hourly_count
  FROM participations
  WHERE user_id = v_user_id AND created_at > NOW() - INTERVAL '1 hour';

  IF v_hourly_count >= 10 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 8. Determine status based on visibility
  IF v_activity.visibility IN ('public', 'private_link') THEN
    v_result_status := 'accepted';
  ELSE
    v_result_status := 'pending';
  END IF;

  -- 9. Insert (UNIQUE constraint prevents double join)
  INSERT INTO participations (activity_id, user_id, status, created_at)
  VALUES (p_activity_id, v_user_id, v_result_status, now());

  RETURN v_result_status;
END;
$$;

REVOKE EXECUTE ON FUNCTION join_activity FROM public;
GRANT EXECUTE ON FUNCTION join_activity TO authenticated;

-- ============================================================================
-- FUNCTION: accept_participation
-- ============================================================================
CREATE OR REPLACE FUNCTION accept_participation(
  p_participation_id UUID
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
  v_current_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Get participation + lock
  SELECT p.id, p.activity_id, p.user_id, p.status, a.creator_id, a.status AS activity_status, a.max_participants
  INTO v_participation
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.id = p_participation_id
  FOR UPDATE OF p;

  IF v_participation IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Caller must be activity creator
  IF v_user_id != v_participation.creator_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Activity must be active
  IF v_participation.activity_status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Participation must be pending
  IF v_participation.status != 'pending' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Check seat count before accepting
  SELECT count(*) INTO v_current_count
  FROM participations
  WHERE activity_id = v_participation.activity_id AND status = 'accepted';

  IF v_current_count >= v_participation.max_participants THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Accept
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations SET status = 'accepted' WHERE id = p_participation_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION accept_participation FROM public;
GRANT EXECUTE ON FUNCTION accept_participation TO authenticated;

-- ============================================================================
-- FUNCTION: refuse_participation
-- ============================================================================
CREATE OR REPLACE FUNCTION refuse_participation(
  p_participation_id UUID
)
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

  SELECT p.id, p.status, a.creator_id, a.status AS activity_status
  INTO v_participation
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.id = p_participation_id
  FOR UPDATE OF p;

  IF v_participation IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id != v_participation.creator_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_participation.activity_status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_participation.status != 'pending' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations SET status = 'refused' WHERE id = p_participation_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION refuse_participation FROM public;
GRANT EXECUTE ON FUNCTION refuse_participation TO authenticated;

-- ============================================================================
-- FUNCTION: leave_activity
-- ============================================================================
CREATE OR REPLACE FUNCTION leave_activity(
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_participation RECORD;
  v_activity_status TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Lock participation row (prevents race with remove_participant)
  SELECT p.id, p.status
  INTO v_participation
  FROM participations p
  WHERE p.activity_id = p_activity_id AND p.user_id = v_user_id
  FOR UPDATE;

  IF v_participation IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Can't leave if removed
  IF v_participation.status = 'removed' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Can only leave accepted or pending
  IF v_participation.status NOT IN ('accepted', 'pending') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Activity must be active
  SELECT status INTO v_activity_status FROM activities WHERE id = p_activity_id;
  IF v_activity_status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Set withdrawn + record when
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET status = 'withdrawn', left_at = now()
  WHERE id = v_participation.id;
END;
$$;

REVOKE EXECUTE ON FUNCTION leave_activity FROM public;
GRANT EXECUTE ON FUNCTION leave_activity TO authenticated;

-- ============================================================================
-- FUNCTION: remove_participant
-- ============================================================================
CREATE OR REPLACE FUNCTION remove_participant(
  p_participation_id UUID
)
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

  SELECT p.id, p.user_id, p.status, a.creator_id
  INTO v_participation
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.id = p_participation_id
  FOR UPDATE OF p;

  IF v_participation IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Caller must be activity creator
  IF v_user_id != v_participation.creator_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Can't remove the creator
  IF v_participation.user_id = v_participation.creator_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Must be currently accepted
  IF v_participation.status != 'accepted' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Remove (final — can't be re-accepted)
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations SET status = 'removed' WHERE id = p_participation_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION remove_participant FROM public;
GRANT EXECUTE ON FUNCTION remove_participant TO authenticated;

-- ============================================================================
-- FUNCTION: cancel_activity
-- ============================================================================
CREATE OR REPLACE FUNCTION cancel_activity(
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, creator_id, status
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id
  FOR UPDATE;

  IF v_activity IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id != v_activity.creator_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE activities SET status = 'cancelled', updated_at = now() WHERE id = p_activity_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION cancel_activity FROM public;
GRANT EXECUTE ON FUNCTION cancel_activity TO authenticated;
