-- Migration 00029: Sprint 4 security audit fixes
-- Fixes: wall blocking, invite token exposure, participant view, rate limit, notification prefs

-- ============================================================================
-- FIX 1: Wall messages — CONFIRMED unidirectional blocking is correct per SECURITY.md
-- "A bloque B → A ne voit plus les messages de B. B voit toujours les messages de A."
-- Original policy in 00006 is correct. No change needed.
-- ============================================================================

-- ============================================================================
-- FIX 2 (HIGH): Invite token — restrict to creator only via RPC function
-- Remove direct table query exposure, use a dedicated function
-- ============================================================================
CREATE OR REPLACE FUNCTION get_own_invite_token(
  p_activity_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_token UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Only the creator can get the invite token
  SELECT invite_token INTO v_token
  FROM activities
  WHERE id = p_activity_id AND creator_id = v_user_id AND deleted_at IS NULL;

  IF v_token IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  RETURN v_token;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_own_invite_token FROM anon;
GRANT EXECUTE ON FUNCTION get_own_invite_token TO authenticated;

-- ============================================================================
-- FIX 3 (HIGH): Activity participants view — add blocked user + deleted_at filter
-- ============================================================================
DROP VIEW IF EXISTS activity_participants;

CREATE VIEW activity_participants AS
SELECT
  p.id AS participation_id,
  p.activity_id,
  p.user_id,
  p.status,
  p.created_at,
  p.left_at,
  a.creator_id,
  pp.display_name,
  pp.avatar_url
FROM participations p
JOIN activities a ON a.id = p.activity_id
JOIN public_profiles pp ON pp.id = p.user_id
WHERE a.creator_id = auth.uid()
  AND p.user_id != a.creator_id
  AND p.status != 'removed'
  AND a.deleted_at IS NULL
  AND p.user_id NOT IN (
    SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid()
  );

GRANT SELECT ON activity_participants TO authenticated;

-- ============================================================================
-- FIX 4 (MEDIUM): Rate limit back to 10/hour in join_activity
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

  SELECT count(*) INTO v_current_count
  FROM participations
  WHERE activity_id = p_activity_id AND status = 'accepted';

  IF v_current_count >= v_activity.max_participants THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Rate limit: 10 per hour (fixed from 100)
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
-- FIX 5 (MEDIUM): Notification preference check — use proper boolean check
-- ============================================================================
CREATE OR REPLACE FUNCTION create_notification(
  p_user_id UUID,
  p_type TEXT,
  p_title TEXT,
  p_body TEXT,
  p_data JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_notification_id UUID;
  v_prefs JSONB;
  v_pref_value TEXT;
BEGIN
  SELECT notification_preferences INTO v_prefs FROM users WHERE id = p_user_id;

  -- Check if the preference exists and is explicitly disabled
  IF v_prefs IS NOT NULL AND v_prefs ? p_type THEN
    v_pref_value := v_prefs ->> p_type;
    IF v_pref_value IS NOT NULL AND v_pref_value NOT IN ('true', '1') THEN
      RETURN NULL;
    END IF;
  END IF;

  INSERT INTO notifications (user_id, type, title, body, data, created_at)
  VALUES (p_user_id, p_type, p_title, p_body, p_data, now())
  RETURNING id INTO v_notification_id;

  RETURN v_notification_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_notification FROM anon, authenticated;

-- ============================================================================
-- FIX 6 (MEDIUM): my_joined_activities — add deleted_at filter
-- ============================================================================
DROP VIEW IF EXISTS my_joined_activities;

CREATE VIEW my_joined_activities AS
SELECT
  a.id, a.creator_id, a.sport_id, a.title, a.description, a.level,
  a.max_participants, a.starts_at, a.duration, a.visibility,
  a.status, a.deleted_at, a.created_at, a.updated_at,
  ST_X(a.location_start::geometry) AS lng,
  ST_Y(a.location_start::geometry) AS lat,
  pp.display_name AS creator_name,
  pp.avatar_url AS creator_avatar,
  s.key AS sport_key,
  s.icon AS sport_icon,
  s.category AS sport_category,
  (SELECT count(*)::int FROM participations p
   WHERE p.activity_id = a.id AND p.status = 'accepted') AS participant_count
FROM activities a
JOIN participations par ON par.activity_id = a.id
  AND par.user_id = auth.uid()
  AND par.status = 'accepted'
JOIN public_profiles pp ON a.creator_id = pp.id
JOIN sports s ON a.sport_id = s.id
WHERE a.creator_id != auth.uid()
  AND a.deleted_at IS NULL;

GRANT SELECT ON my_joined_activities TO authenticated;
