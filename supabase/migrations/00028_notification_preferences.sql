-- Migration 00028: notification_preferences column on users
-- JSONB with toggles per notification type. User-controlled, added to whitelist.

ALTER TABLE users ADD COLUMN notification_preferences JSONB DEFAULT '{
  "join_request": true,
  "participant_joined": true,
  "request_accepted": true,
  "request_refused": true,
  "participant_removed": true,
  "participant_left": true,
  "activity_cancelled": true,
  "activity_updated": true
}'::jsonb NOT NULL;

-- Update whitelist trigger to allow notification_preferences
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

  -- WHITELIST: force ALL non-allowed columns to their old values
  NEW.id := OLD.id;
  NEW.email := OLD.email;
  NEW.created_at := OLD.created_at;
  NEW.date_of_birth := OLD.date_of_birth;
  NEW.is_admin := OLD.is_admin;
  NEW.tier := OLD.tier;
  NEW.is_pro_verified := OLD.is_pro_verified;
  NEW.pro_verified_at := OLD.pro_verified_at;
  NEW.suspended_at := OLD.suspended_at;
  NEW.phone_verified := OLD.phone_verified;
  NEW.phone_verified_at := OLD.phone_verified_at;
  NEW.accepted_tos_at := OLD.accepted_tos_at;
  NEW.accepted_privacy_at := OLD.accepted_privacy_at;
  NEW.push_token := OLD.push_token;

  -- Allowed: display_name, avatar_url, bio, sports, levels_per_sport, notification_preferences

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- Update create_notification to respect preferences
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
BEGIN
  -- Check user's notification preferences
  SELECT notification_preferences INTO v_prefs FROM users WHERE id = p_user_id;

  -- If the preference exists and is explicitly false, skip
  IF v_prefs IS NOT NULL AND (v_prefs ->> p_type) = 'false' THEN
    RETURN NULL;
  END IF;

  INSERT INTO notifications (user_id, type, title, body, data, created_at)
  VALUES (p_user_id, p_type, p_title, p_body, p_data, now())
  RETURNING id INTO v_notification_id;

  RETURN v_notification_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_notification FROM anon, authenticated;
