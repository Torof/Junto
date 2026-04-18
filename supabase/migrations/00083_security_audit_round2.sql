-- Migration 00083: security audit round 2
-- Fix create_or_get_conversation bypass, protect requires_presence,
-- add suspension checks to notification/tutorial functions.

-- ============================================================================
-- 1. create_or_get_conversation: block direct creation, only return existing active
-- ============================================================================
CREATE OR REPLACE FUNCTION create_or_get_conversation(
  p_other_user_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_user_1 UUID;
  v_user_2 UUID;
  v_conversation_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_other_user_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_1 < p_other_user_id THEN
    v_user_1 := v_user_id;
    v_user_2 := p_other_user_id;
  ELSE
    v_user_1 := p_other_user_id;
    v_user_2 := v_user_id;
  END IF;

  SELECT id INTO v_conversation_id
  FROM conversations
  WHERE user_1 = v_user_1 AND user_2 = v_user_2
    AND status = 'active';

  IF v_conversation_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  RETURN v_conversation_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_or_get_conversation FROM anon;
GRANT EXECUTE ON FUNCTION create_or_get_conversation TO authenticated;

-- ============================================================================
-- 2. handle_activity_update: protect requires_presence when participants exist
-- ============================================================================
CREATE OR REPLACE FUNCTION handle_activity_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    NEW.updated_at := now();
    RETURN NEW;
  END IF;

  NEW.creator_id := OLD.creator_id;
  NEW.status := OLD.status;
  NEW.invite_token := OLD.invite_token;
  NEW.created_at := OLD.created_at;

  IF (SELECT count(*) FROM participations
      WHERE activity_id = NEW.id AND status = 'accepted' AND user_id != OLD.creator_id) > 0
  THEN
    NEW.location_start := OLD.location_start;
    NEW.location_meeting := OLD.location_meeting;
    NEW.location_end := OLD.location_end;
    NEW.location_objective := OLD.location_objective;
    NEW.objective_name := OLD.objective_name;
    NEW.starts_at := OLD.starts_at;
    NEW.level := OLD.level;
    NEW.max_participants := OLD.max_participants;
    NEW.visibility := OLD.visibility;
    NEW.requires_presence := OLD.requires_presence;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- ============================================================================
-- 3. mark_notification_read: add suspension check
-- ============================================================================
CREATE OR REPLACE FUNCTION mark_notification_read(p_notification_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE notifications SET read = TRUE
  WHERE id = p_notification_id AND user_id = v_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION mark_notification_read FROM anon;
GRANT EXECUTE ON FUNCTION mark_notification_read TO authenticated;

-- ============================================================================
-- 4. mark_all_notifications_read: add suspension check
-- ============================================================================
CREATE OR REPLACE FUNCTION mark_all_notifications_read()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE notifications SET read = TRUE
  WHERE user_id = v_user_id AND read = FALSE;
END;
$$;

REVOKE EXECUTE ON FUNCTION mark_all_notifications_read FROM anon;
GRANT EXECUTE ON FUNCTION mark_all_notifications_read TO authenticated;
