-- Migration 00066: security audit fixes
-- Addresses findings from the audit after the cancellation/presence/push sprint.

-- ============================================================================
-- C1: shared-secret authentication for the send-push edge function.
-- A tiny app_config table holds the secret; only SECURITY DEFINER functions
-- can read it. The trigger and direct callers send it as a header; the edge
-- function rejects requests without it.
--
-- After applying this migration, set the secret manually in SQL Editor:
--   INSERT INTO app_config (name, value) VALUES
--     ('push_webhook_secret', '<generate a long random string here>');
-- Then set the same value as PUSH_WEBHOOK_SECRET env var on the edge function.
-- ============================================================================
CREATE TABLE IF NOT EXISTS app_config (
  name TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
ALTER TABLE app_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_config FORCE ROW LEVEL SECURITY;
-- No grants — only accessible from SECURITY DEFINER functions.

CREATE OR REPLACE FUNCTION trigger_send_push()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_secret TEXT;
BEGIN
  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';
  IF v_secret IS NULL THEN
    RETURN NEW; -- not configured yet, silently skip
  END IF;

  PERFORM net.http_post(
    url := 'https://lvjlthzdydzatcvwwriu.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-junto-push-secret', v_secret
    ),
    body := jsonb_build_object(
      'user_id', NEW.user_id,
      'title', NEW.title,
      'body', NEW.body,
      'data', NEW.data
    )
  );
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION trigger_send_push FROM anon, authenticated;

-- Update send_private_message to use the secret on its direct push call.
CREATE OR REPLACE FUNCTION send_private_message(
  p_conversation_id UUID,
  p_content TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_conversation RECORD;
  v_other_user_id UUID;
  v_message_id UUID;
  v_recent_count INTEGER;
  v_sender_name TEXT;
  v_secret TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, user_1, user_2 INTO v_conversation FROM conversations WHERE id = p_conversation_id;
  IF v_conversation IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id != v_conversation.user_1 AND v_user_id != v_conversation.user_2 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_other_user_id := CASE WHEN v_user_id = v_conversation.user_1 THEN v_conversation.user_2 ELSE v_conversation.user_1 END;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_other_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = v_other_user_id)
       OR (blocker_id = v_other_user_id AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_dm_' || p_conversation_id::text));

  SELECT count(*) INTO v_recent_count
  FROM private_messages
  WHERE conversation_id = p_conversation_id
    AND sender_id = v_user_id
    AND created_at > NOW() - INTERVAL '1 minute';

  IF v_recent_count >= 1 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF trim(p_content) = '' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  INSERT INTO private_messages (conversation_id, sender_id, receiver_id, content, created_at)
  VALUES (p_conversation_id, v_user_id, v_other_user_id, trim(p_content), now())
  RETURNING id INTO v_message_id;

  UPDATE conversations SET last_message_at = now() WHERE id = p_conversation_id;

  SELECT display_name INTO v_sender_name FROM users WHERE id = v_user_id;
  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';

  IF v_secret IS NOT NULL THEN
    PERFORM net.http_post(
      url := 'https://lvjlthzdydzatcvwwriu.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-junto-push-secret', v_secret
      ),
      body := jsonb_build_object(
        'user_id', v_other_user_id,
        'title', coalesce(v_sender_name, 'Junto'),
        'body', 'Tu as reçu un message',
        'data', jsonb_build_object('conversation_id', p_conversation_id, 'type', 'new_message')
      )
    );
  END IF;

  RETURN v_message_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION send_private_message FROM anon;
GRANT EXECUTE ON FUNCTION send_private_message TO authenticated;


-- ============================================================================
-- C4 (CRITICAL): restore the full whitelist on users
-- Migration 00052 rewrote handle_user_update and accidentally dropped
-- push_token and reliability_score from the protected list, making them
-- user-writable via direct UPDATE.
-- ============================================================================
CREATE OR REPLACE FUNCTION handle_user_update()
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

  -- WHITELIST: any non-allowed column is forced back to its OLD value.
  -- Allowed (writable by the user): display_name, avatar_url, bio, sports, levels_per_sport, notification_preferences
  NEW.id := OLD.id;
  NEW.email := OLD.email;
  NEW.created_at := OLD.created_at;
  NEW.date_of_birth := OLD.date_of_birth;
  NEW.phone_verified := OLD.phone_verified;
  NEW.phone_verified_at := OLD.phone_verified_at;
  NEW.tier := OLD.tier;
  NEW.is_pro_verified := OLD.is_pro_verified;
  NEW.pro_verified_at := OLD.pro_verified_at;
  NEW.is_admin := OLD.is_admin;
  NEW.suspended_at := OLD.suspended_at;
  NEW.accepted_tos_at := OLD.accepted_tos_at;
  NEW.accepted_privacy_at := OLD.accepted_privacy_at;
  NEW.tutorial_seen_at := OLD.tutorial_seen_at;
  NEW.push_token := OLD.push_token;
  NEW.reliability_score := OLD.reliability_score;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION handle_user_update FROM anon, authenticated;

-- ============================================================================
-- H1: drop the demo activity helpers — no longer used by the tutorial
-- (tutorial now uses the nearest real activity).
-- ============================================================================
DROP FUNCTION IF EXISTS seed_demo_activity(FLOAT, FLOAT);
DROP FUNCTION IF EXISTS delete_demo_activity(UUID);

-- ============================================================================
-- H5: register_push_token must steal the token from any previous owner.
-- A device that signed in with user A then user B reports the same Expo token —
-- without this, user A's row still points at it and gets B's pushes.
-- Also: stricter format validation.
-- ============================================================================
CREATE OR REPLACE FUNCTION register_push_token(p_token TEXT)
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

  IF p_token IS NULL OR char_length(p_token) < 20 OR char_length(p_token) > 200 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_token !~ '^Exp(o|onent)PushToken\[.+\]$' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  -- Detach the token from any previous owner first.
  UPDATE users SET push_token = NULL WHERE push_token = p_token AND id != v_user_id;
  UPDATE users SET push_token = p_token WHERE id = v_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION register_push_token FROM anon;
GRANT EXECUTE ON FUNCTION register_push_token TO authenticated;

-- ============================================================================
-- M6: check_alerts_for_activity must skip blocked relationships in either direction.
-- ============================================================================
CREATE OR REPLACE FUNCTION check_alerts_for_activity(
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_activity RECORD;
  v_alert RECORD;
  v_sport_key TEXT;
  v_activity_date DATE;
BEGIN
  SELECT id, title, sport_id, location_start, location_meeting, level, creator_id, starts_at
  INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;

  SELECT key INTO v_sport_key FROM sports WHERE id = v_activity.sport_id;
  v_activity_date := v_activity.starts_at::date;

  FOR v_alert IN
    SELECT a.id, a.user_id
    FROM activity_alerts a
    WHERE a.user_id != v_activity.creator_id
      AND (a.sport_key IS NULL OR a.sport_key = v_sport_key)
      AND (a.levels IS NULL OR v_activity.level = ANY(a.levels))
      AND (a.starts_on IS NULL OR v_activity_date >= a.starts_on)
      AND (a.ends_on IS NULL OR v_activity_date <= a.ends_on)
      AND NOT EXISTS (
        SELECT 1 FROM blocked_users b
        WHERE (b.blocker_id = v_activity.creator_id AND b.blocked_id = a.user_id)
           OR (b.blocker_id = a.user_id AND b.blocked_id = v_activity.creator_id)
      )
      AND (
        ST_DWithin(a.location, v_activity.location_start, a.radius_km * 1000)
        OR (v_activity.location_meeting IS NOT NULL
            AND ST_DWithin(a.location, v_activity.location_meeting, a.radius_km * 1000))
      )
  LOOP
    PERFORM create_notification(
      v_alert.user_id,
      'alert_match',
      'Nouvelle activité',
      v_activity.title || ' correspond à ton alerte',
      jsonb_build_object('activity_id', p_activity_id)
    );
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION check_alerts_for_activity FROM anon, authenticated;

-- ============================================================================
-- H3 (defensive): re-apply REVOKE/GRANT on the presence functions touched in 00063.
-- CREATE OR REPLACE preserves grants, but explicit is better than implicit.
-- ============================================================================
REVOKE EXECUTE ON FUNCTION confirm_presence_via_geo FROM anon;
GRANT EXECUTE ON FUNCTION confirm_presence_via_geo TO authenticated;

REVOKE EXECUTE ON FUNCTION create_presence_token FROM anon;
GRANT EXECUTE ON FUNCTION create_presence_token TO authenticated;

REVOKE EXECUTE ON FUNCTION confirm_presence_via_token FROM anon;
GRANT EXECUTE ON FUNCTION confirm_presence_via_token TO authenticated;

REVOKE EXECUTE ON FUNCTION creator_override_presence FROM anon;
GRANT EXECUTE ON FUNCTION creator_override_presence TO authenticated;

-- ============================================================================
-- M4: cap the leave_activity reason length defensively (stop abuse via push body).
-- The function already trims; just enforce the 200-char cap explicitly.
-- ============================================================================
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

  SELECT id, status, starts_at, creator_id, title INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_is_late := v_activity.starts_at - INTERVAL '12 hours' < now();

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
