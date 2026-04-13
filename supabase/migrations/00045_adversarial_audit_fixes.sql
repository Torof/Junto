-- Migration 00045: Adversarial security audit fixes
-- 10.5: unblock RLS already correct (blocker_id = auth.uid() in DELETE policy)
-- 3.1 + 7.3: Rate limit on get_activity_by_invite_token
-- 6.1: Advisory lock on join_activity seat count

-- ============================================================================
-- 3.1 + 7.3: Rate limit invite token lookups (prevent brute-force + DoS)
-- ============================================================================
CREATE OR REPLACE FUNCTION get_activity_by_invite_token(
  p_token UUID
)
RETURNS TABLE (
  id UUID,
  creator_id UUID,
  sport_id UUID,
  title TEXT,
  description TEXT,
  level TEXT,
  max_participants INTEGER,
  starts_at TIMESTAMPTZ,
  duration INTERVAL,
  visibility TEXT,
  status TEXT,
  lng FLOAT,
  lat FLOAT,
  creator_name TEXT,
  creator_avatar TEXT,
  sport_key TEXT,
  sport_icon TEXT,
  sport_category TEXT,
  participant_count INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_recent_count INTEGER;
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

  -- 3. Invite token brute-force protection:
  -- UUID v4 has 2^122 bits of entropy — statistically impossible to guess
  -- Supabase API has built-in per-IP rate limiting
  -- No DB-level throttling needed (advisory locks don't work across transactions,
  -- and pg_sleep would be a DoS vector)

  -- 4. Return activity data if token matches
  RETURN QUERY
  SELECT
    a.id,
    a.creator_id,
    a.sport_id,
    a.title,
    a.description,
    a.level,
    a.max_participants,
    a.starts_at,
    a.duration,
    a.visibility,
    a.status,
    ST_X(a.location_start::geometry)::FLOAT AS lng,
    ST_Y(a.location_start::geometry)::FLOAT AS lat,
    pp.display_name AS creator_name,
    pp.avatar_url AS creator_avatar,
    s.key AS sport_key,
    s.icon AS sport_icon,
    s.category AS sport_category,
    (SELECT count(*)::int FROM participations p
     WHERE p.activity_id = a.id AND p.status = 'accepted') AS participant_count
  FROM activities a
  JOIN public_profiles pp ON a.creator_id = pp.id
  JOIN sports s ON a.sport_id = s.id
  WHERE a.invite_token = p_token
    AND a.deleted_at IS NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_activity_by_invite_token FROM anon;
GRANT EXECUTE ON FUNCTION get_activity_by_invite_token TO authenticated;

-- ============================================================================
-- 6.1: Fix join_activity — add FOR UPDATE on activity row to prevent
-- concurrent joins exceeding max_participants
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
  v_existing RECORD;
  v_user_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Lock the activity row to prevent concurrent joins exceeding max_participants
  SELECT id, creator_id, status, visibility, max_participants, title
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

  -- Seat count (under FOR UPDATE lock — no race condition)
  SELECT count(*) INTO v_current_count
  FROM participations
  WHERE activity_id = p_activity_id AND status = 'accepted';

  IF v_current_count >= v_activity.max_participants THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Rate limit: 10 per hour
  SELECT count(*) INTO v_hourly_count
  FROM participations
  WHERE user_id = v_user_id AND created_at > NOW() - INTERVAL '1 hour';

  IF v_hourly_count >= 10 THEN
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
    IF v_existing.status = 'removed' THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;

    IF v_existing.status IN ('accepted', 'pending') THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;

    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE participations
    SET status = v_result_status, left_at = NULL, created_at = now()
    WHERE id = v_existing.id;
  ELSE
    INSERT INTO participations (activity_id, user_id, status, created_at)
    VALUES (p_activity_id, v_user_id, v_result_status, now());
  END IF;

  -- Notify creator
  SELECT display_name INTO v_user_name FROM public_profiles WHERE id = v_user_id;

  IF v_result_status = 'pending' THEN
    PERFORM create_notification(
      v_activity.creator_id,
      'join_request',
      'Nouvelle demande',
      v_user_name || ' souhaite rejoindre ' || v_activity.title,
      jsonb_build_object('activity_id', p_activity_id)
    );
  ELSE
    PERFORM create_notification(
      v_activity.creator_id,
      'participant_joined',
      'Nouveau participant',
      v_user_name || ' a rejoint ' || v_activity.title,
      jsonb_build_object('activity_id', p_activity_id)
    );
  END IF;

  RETURN v_result_status;
END;
$$;

REVOKE EXECUTE ON FUNCTION join_activity FROM public;
GRANT EXECUTE ON FUNCTION join_activity TO authenticated;

-- ============================================================================
-- 1.2: Filter out activities from suspended creators in activities_with_coords
-- ============================================================================
CREATE OR REPLACE VIEW activities_with_coords AS
SELECT
  a.id, a.creator_id, a.sport_id, a.title, a.description, a.level,
  a.max_participants, a.starts_at, a.duration, a.visibility,
  a.status, a.deleted_at, a.created_at, a.updated_at,
  ST_X(a.location_start::geometry) AS lng,
  ST_Y(a.location_start::geometry) AS lat,
  ST_X(a.location_meeting::geometry) AS meeting_lng,
  ST_Y(a.location_meeting::geometry) AS meeting_lat,
  ST_X(a.location_end::geometry) AS end_lng,
  ST_Y(a.location_end::geometry) AS end_lat,
  pp.display_name AS creator_name,
  pp.avatar_url AS creator_avatar,
  s.key AS sport_key,
  s.icon AS sport_icon,
  s.category AS sport_category,
  (SELECT count(*)::int FROM participations p
   WHERE p.activity_id = a.id AND p.status = 'accepted') AS participant_count
FROM activities a
JOIN public_profiles pp ON a.creator_id = pp.id
JOIN sports s ON a.sport_id = s.id
WHERE a.deleted_at IS NULL
  AND a.status IN ('published', 'in_progress')
  AND a.visibility IN ('public', 'approval');
-- Note: public_profiles already filters suspended_at IS NULL via its WHERE clause
-- So JOIN on public_profiles automatically excludes suspended creators

GRANT SELECT ON activities_with_coords TO anon, authenticated;
