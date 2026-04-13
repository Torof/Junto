-- Migration 00046: Third security audit fixes

-- ============================================================================
-- HIGH: Fix conversations.initiated_by missing ON DELETE CASCADE
-- Without this, account deletion fails with FK violation for any user
-- who initiated a conversation
-- ============================================================================
ALTER TABLE conversations DROP CONSTRAINT IF EXISTS conversations_initiated_by_fkey;
ALTER TABLE conversations ADD CONSTRAINT conversations_initiated_by_fkey
  FOREIGN KEY (initiated_by) REFERENCES users(id) ON DELETE CASCADE;

-- ============================================================================
-- MEDIUM: Trim and validate titles in create_activity to prevent whitespace-only
-- ============================================================================
-- Already handled by updating create_activity to trim title
CREATE OR REPLACE FUNCTION create_activity(
  p_sport_id UUID,
  p_title TEXT,
  p_description TEXT,
  p_level TEXT,
  p_max_participants INTEGER,
  p_start_lng FLOAT,
  p_start_lat FLOAT,
  p_meeting_lng FLOAT DEFAULT NULL,
  p_meeting_lat FLOAT DEFAULT NULL,
  p_end_lng FLOAT DEFAULT NULL,
  p_end_lat FLOAT DEFAULT NULL,
  p_starts_at TIMESTAMPTZ DEFAULT NULL,
  p_duration TEXT DEFAULT '2 hours',
  p_visibility TEXT DEFAULT 'public'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_tier TEXT;
  v_phone_verified BOOLEAN;
  v_monthly_count INTEGER;
  v_daily_count INTEGER;
  v_activity_id UUID;
  v_title TEXT;
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

  -- 3. Trim and validate title
  v_title := trim(p_title);
  IF char_length(v_title) < 3 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 4. Phone verified + tier check (BEFORE lock)
  SELECT phone_verified, tier INTO v_phone_verified, v_tier
  FROM users WHERE id = v_user_id;

  IF NOT v_phone_verified THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 5. Tier check for private visibility (BEFORE lock)
  IF p_visibility IN ('private_link', 'private_link_approval') AND v_tier = 'free' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 6. Validate starts_at (BEFORE lock)
  IF p_starts_at IS NULL OR p_starts_at <= NOW() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 7. Rate limiting with advisory lock (AFTER validation)
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_create_activity'));

  SELECT count(*) INTO v_daily_count
  FROM activities
  WHERE creator_id = v_user_id AND created_at > NOW() - INTERVAL '1 day';

  IF v_daily_count >= 20 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_tier = 'free' THEN
    SELECT count(*) INTO v_monthly_count
    FROM activities
    WHERE creator_id = v_user_id AND created_at > NOW() - INTERVAL '1 month';

    IF v_monthly_count >= 4 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  -- 8. Insert activity
  PERFORM set_config('junto.bypass_lock', 'true', true);

  INSERT INTO activities (
    creator_id, sport_id, title, description, level,
    max_participants, location_start, location_meeting, location_end,
    starts_at, duration, visibility, status, created_at, updated_at
  ) VALUES (
    v_user_id, p_sport_id, v_title, trim(p_description), p_level,
    p_max_participants,
    ST_SetSRID(ST_MakePoint(p_start_lng, p_start_lat), 4326)::geography,
    CASE WHEN p_meeting_lng IS NOT NULL AND p_meeting_lat IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_meeting_lng, p_meeting_lat), 4326)::geography
      ELSE NULL END,
    CASE WHEN p_end_lng IS NOT NULL AND p_end_lat IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_end_lng, p_end_lat), 4326)::geography
      ELSE NULL END,
    p_starts_at, p_duration::interval, p_visibility, 'published', now(), now()
  ) RETURNING id INTO v_activity_id;

  -- 9. Auto-insert creator as accepted participant
  INSERT INTO participations (activity_id, user_id, status, created_at)
  VALUES (v_activity_id, v_user_id, 'accepted', now());

  RETURN v_activity_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_activity FROM anon;
GRANT EXECUTE ON FUNCTION create_activity TO authenticated;

-- ============================================================================
-- MEDIUM: Also trim title/description in update_activity
-- ============================================================================
CREATE OR REPLACE FUNCTION update_activity(
  p_activity_id UUID,
  p_title TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_level TEXT DEFAULT NULL,
  p_max_participants INTEGER DEFAULT NULL,
  p_start_lng FLOAT DEFAULT NULL,
  p_start_lat FLOAT DEFAULT NULL,
  p_meeting_lng FLOAT DEFAULT NULL,
  p_meeting_lat FLOAT DEFAULT NULL,
  p_starts_at TIMESTAMPTZ DEFAULT NULL,
  p_duration TEXT DEFAULT NULL,
  p_visibility TEXT DEFAULT NULL
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
  v_trimmed_title TEXT;
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

  -- 3. Trim and validate title if provided
  IF p_title IS NOT NULL THEN
    v_trimmed_title := trim(p_title);
    IF char_length(v_trimmed_title) < 3 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  -- 4. Get activity + verify ownership
  SELECT id, creator_id, status, title
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

  -- 5. Activity must be active
  IF v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 6. Validate starts_at if provided
  IF p_starts_at IS NOT NULL AND p_starts_at <= NOW() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 7. Apply updates (trigger handles field locking for protected fields)
  UPDATE activities SET
    title = COALESCE(v_trimmed_title, title),
    description = CASE WHEN p_description IS NOT NULL THEN trim(p_description) ELSE description END,
    level = COALESCE(p_level, level),
    max_participants = COALESCE(p_max_participants, max_participants),
    location_start = CASE
      WHEN p_start_lng IS NOT NULL AND p_start_lat IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_start_lng, p_start_lat), 4326)::geography
      ELSE location_start
    END,
    location_meeting = CASE
      WHEN p_meeting_lng IS NOT NULL AND p_meeting_lat IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_meeting_lng, p_meeting_lat), 4326)::geography
      ELSE location_meeting
    END,
    starts_at = COALESCE(p_starts_at, starts_at),
    duration = CASE WHEN p_duration IS NOT NULL THEN p_duration::interval ELSE duration END,
    visibility = COALESCE(p_visibility, visibility)
  WHERE id = p_activity_id;

  -- 8. Notify all accepted participants (except creator)
  FOR v_participant IN
    SELECT user_id FROM participations
    WHERE activity_id = p_activity_id AND status = 'accepted' AND user_id != v_user_id
  LOOP
    PERFORM create_notification(
      v_participant.user_id,
      'activity_updated',
      'Activité modifiée',
      v_activity.title || ' a été modifiée',
      jsonb_build_object('activity_id', p_activity_id)
    );
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION update_activity FROM anon;
GRANT EXECUTE ON FUNCTION update_activity TO authenticated;
