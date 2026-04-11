-- Migration 00027: update_activity function
-- Creator can edit their activity. Trigger handles field locking.
-- Notifies all accepted participants on any change.

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
  v_changed BOOLEAN := false;
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

  -- 3. Get activity + verify ownership
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

  -- 4. Activity must be active
  IF v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 5. Validate starts_at if provided
  IF p_starts_at IS NOT NULL AND p_starts_at <= NOW() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 6. Apply updates (trigger handles field locking for protected fields)
  UPDATE activities SET
    title = COALESCE(p_title, title),
    description = COALESCE(p_description, description),
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

  -- 7. Notify all accepted participants (except creator)
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
