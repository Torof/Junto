-- Migration 00044: Pre-launch security audit fixes
-- C-001, H-001, H-002, H-003, M-002

-- ============================================================================
-- C-001: Ensure left_at column exists (safety check for migration order)
-- ============================================================================
ALTER TABLE participations ADD COLUMN IF NOT EXISTS left_at TIMESTAMPTZ;

-- ============================================================================
-- H-001: Add suspension check to authenticated activities SELECT policy
-- ============================================================================
DROP POLICY IF EXISTS "activities_select_authenticated" ON activities;

CREATE POLICY "activities_select_authenticated"
  ON activities FOR SELECT
  TO authenticated
  USING (
    NOT EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND suspended_at IS NOT NULL)
    AND (
      (
        status IN ('published', 'in_progress')
        AND deleted_at IS NULL
        AND NOT EXISTS (
          SELECT 1 FROM users WHERE id = activities.creator_id AND suspended_at IS NOT NULL
        )
        AND creator_id NOT IN (
          SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid()
        )
      )
      OR auth.uid() = creator_id
      OR EXISTS (
        SELECT 1 FROM participations
        WHERE activity_id = activities.id AND user_id = auth.uid()
      )
    )
  );

-- ============================================================================
-- H-002: Validate notification_preferences JSONB structure in whitelist trigger
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
  NEW.reliability_score := OLD.reliability_score;

  -- Validate notification_preferences if changed
  IF NEW.notification_preferences IS DISTINCT FROM OLD.notification_preferences THEN
    BEGIN
      IF NEW.notification_preferences IS NOT NULL THEN
        -- Must be a JSONB object
        IF jsonb_typeof(NEW.notification_preferences) != 'object' THEN
          NEW.notification_preferences := OLD.notification_preferences;
        ELSE
          -- All values must be boolean (true/false)
          IF EXISTS (
            SELECT 1 FROM jsonb_each(NEW.notification_preferences) AS kv
            WHERE jsonb_typeof(kv.value) != 'boolean'
          ) THEN
            NEW.notification_preferences := OLD.notification_preferences;
          END IF;
        END IF;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      NEW.notification_preferences := OLD.notification_preferences;
    END;
  END IF;

  -- Allowed: display_name, avatar_url, bio, sports, levels_per_sport, notification_preferences

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- ============================================================================
-- H-003: Fix create_activity — fetch tier BEFORE advisory lock
-- ============================================================================
DROP FUNCTION IF EXISTS create_activity(UUID, TEXT, TEXT, TEXT, INTEGER, FLOAT, FLOAT, FLOAT, FLOAT, FLOAT, FLOAT, TIMESTAMPTZ, TEXT, TEXT);

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

  -- 3. Phone verified + tier check (BEFORE lock)
  SELECT phone_verified, tier INTO v_phone_verified, v_tier
  FROM users WHERE id = v_user_id;

  IF NOT v_phone_verified THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 4. Tier check for private visibility (BEFORE lock)
  IF p_visibility IN ('private_link', 'private_link_approval') AND v_tier = 'free' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 5. Validate starts_at (BEFORE lock)
  IF p_starts_at IS NULL OR p_starts_at <= NOW() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 6. Rate limiting with advisory lock (AFTER validation)
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

  -- 7. Insert activity
  PERFORM set_config('junto.bypass_lock', 'true', true);

  INSERT INTO activities (
    creator_id, sport_id, title, description, level,
    max_participants, location_start, location_meeting, location_end,
    starts_at, duration, visibility, status, created_at, updated_at
  ) VALUES (
    v_user_id, p_sport_id, p_title, p_description, p_level,
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

  -- 8. Auto-insert creator as accepted participant
  INSERT INTO participations (activity_id, user_id, status, created_at)
  VALUES (v_activity_id, v_user_id, 'accepted', now());

  RETURN v_activity_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_activity FROM anon;
GRANT EXECUTE ON FUNCTION create_activity TO authenticated;

-- ============================================================================
-- M-002: Fix edit functions to strip HTML (triggers don't fire in SECURITY DEFINER)
-- ============================================================================
CREATE OR REPLACE FUNCTION edit_private_message(
  p_message_id UUID,
  p_content TEXT DEFAULT NULL,
  p_delete BOOLEAN DEFAULT false
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_message RECORD;
  v_clean_content TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, sender_id, deleted_at INTO v_message
  FROM private_messages
  WHERE id = p_message_id;

  IF v_message IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id != v_message.sender_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_message.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_delete THEN
    UPDATE private_messages SET deleted_at = now() WHERE id = p_message_id;
  ELSIF p_content IS NOT NULL AND trim(p_content) != '' THEN
    v_clean_content := regexp_replace(regexp_replace(trim(p_content), '<[^>]*>', '', 'g'), '<[^>]*$', '', 'g');
    UPDATE private_messages SET content = v_clean_content, edited_at = now() WHERE id = p_message_id;
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION edit_private_message FROM anon;
GRANT EXECUTE ON FUNCTION edit_private_message TO authenticated;

CREATE OR REPLACE FUNCTION edit_wall_message(
  p_message_id UUID,
  p_content TEXT DEFAULT NULL,
  p_delete BOOLEAN DEFAULT false
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_message RECORD;
  v_activity_status TEXT;
  v_clean_content TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT wm.id, wm.user_id, wm.activity_id, wm.deleted_at INTO v_message
  FROM wall_messages wm
  WHERE wm.id = p_message_id;

  IF v_message IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id != v_message.user_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_message.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT status INTO v_activity_status FROM activities WHERE id = v_message.activity_id;
  IF v_activity_status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_delete THEN
    UPDATE wall_messages SET deleted_at = now() WHERE id = p_message_id;
  ELSIF p_content IS NOT NULL AND trim(p_content) != '' THEN
    v_clean_content := regexp_replace(regexp_replace(trim(p_content), '<[^>]*>', '', 'g'), '<[^>]*$', '', 'g');
    UPDATE wall_messages SET content = v_clean_content, edited_at = now() WHERE id = p_message_id;
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION edit_wall_message FROM anon;
GRANT EXECUTE ON FUNCTION edit_wall_message TO authenticated;
