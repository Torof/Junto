-- Migration 00052: remove premium gates + tutorial system
-- Temporary during chicken-and-egg phase. Re-add gates before monetization launch.

-- ============================================================================
-- 1. Remove premium gates in create_activity
-- ============================================================================
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
  v_daily_count INTEGER;
  v_activity_id UUID;
  v_title TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_title := trim(p_title);
  IF char_length(v_title) < 3 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_starts_at IS NULL OR p_starts_at <= NOW() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_create_activity'));

  SELECT count(*) INTO v_daily_count
  FROM activities
  WHERE creator_id = v_user_id AND created_at > NOW() - INTERVAL '1 day';

  IF v_daily_count >= 20 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

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

  INSERT INTO participations (activity_id, user_id, status, created_at)
  VALUES (v_activity_id, v_user_id, 'accepted', now());

  IF p_visibility IN ('public', 'approval') THEN
    PERFORM check_alerts_for_activity(v_activity_id);
  END IF;

  RETURN v_activity_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_activity FROM anon;
GRANT EXECUTE ON FUNCTION create_activity TO authenticated;

-- ============================================================================
-- 2. Remove premium gate in create_alert
-- ============================================================================
CREATE OR REPLACE FUNCTION create_alert(
  p_lng FLOAT,
  p_lat FLOAT,
  p_radius_km INTEGER,
  p_sport_key TEXT DEFAULT NULL,
  p_levels TEXT[] DEFAULT NULL,
  p_starts_on DATE DEFAULT NULL,
  p_ends_on DATE DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_alert_count INTEGER;
  v_alert_id UUID;
  v_allowed_levels TEXT[] := ARRAY['débutant', 'intermédiaire', 'avancé', 'expert'];
  v_level TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT count(*) INTO v_alert_count FROM activity_alerts WHERE user_id = v_user_id;
  IF v_alert_count >= 10 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_levels IS NOT NULL THEN
    IF array_length(p_levels, 1) IS NULL THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    FOREACH v_level IN ARRAY p_levels LOOP
      IF NOT (v_level = ANY(v_allowed_levels)) THEN
        RAISE EXCEPTION 'Operation not permitted';
      END IF;
    END LOOP;
  END IF;

  IF p_starts_on IS NOT NULL AND p_ends_on IS NOT NULL AND p_ends_on < p_starts_on THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_ends_on IS NOT NULL AND p_ends_on < current_date THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  INSERT INTO activity_alerts (user_id, sport_key, location, radius_km, levels, starts_on, ends_on, created_at)
  VALUES (
    v_user_id,
    p_sport_key,
    ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
    p_radius_km,
    p_levels,
    p_starts_on,
    p_ends_on,
    now()
  )
  RETURNING id INTO v_alert_id;

  RETURN v_alert_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_alert FROM anon;
GRANT EXECUTE ON FUNCTION create_alert TO authenticated;

-- ============================================================================
-- 3. Tutorial flag + mark function
-- ============================================================================
ALTER TABLE users ADD COLUMN tutorial_seen_at TIMESTAMPTZ;

-- Whitelist handle_user_update to protect tutorial_seen_at (force OLD unless bypass)
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

  -- WHITELIST: force privileged cols to OLD
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

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION mark_tutorial_seen()
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

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET tutorial_seen_at = now() WHERE id = v_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION mark_tutorial_seen FROM anon;
GRANT EXECUTE ON FUNCTION mark_tutorial_seen TO authenticated;

-- ============================================================================
-- 4. System demo user (fixed UUID)
-- ============================================================================
-- Insert into auth.users directly (superuser context in migrations).
-- Email confirmed instantly. No password (this account never logs in via app).

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data, is_super_admin, is_anonymous
) VALUES (
  '0deadbee-f000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated',
  'demo@junto.app',
  'system-account-no-login',
  now(), now(), now(),
  '{"provider":"system","providers":["system"]}'::jsonb,
  '{}'::jsonb,
  false, false
) ON CONFLICT (id) DO NOTHING;

-- handle_new_user trigger creates public.users row automatically.
-- Override display name and mark tutorial done for system user.
DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE public.users
  SET display_name = 'Junto Demo',
      tutorial_seen_at = now()
  WHERE id = '0deadbee-f000-0000-0000-000000000001';
END $$;

-- ============================================================================
-- 5. seed_demo_activity (creates demo activity near the user)
-- ============================================================================
CREATE OR REPLACE FUNCTION seed_demo_activity(
  p_lng FLOAT,
  p_lat FLOAT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_sport_id UUID;
  v_activity_id UUID;
  v_offset_lng FLOAT := 0.015; -- ~1.5 km
  v_offset_lat FLOAT := 0.015;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Pick a sport (course à pied if present, else first available)
  SELECT id INTO v_sport_id FROM sports WHERE key = 'running' LIMIT 1;
  IF v_sport_id IS NULL THEN
    SELECT id INTO v_sport_id FROM sports ORDER BY key LIMIT 1;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  INSERT INTO activities (
    creator_id, sport_id, title, description, level,
    max_participants, location_start,
    starts_at, duration, visibility, status, created_at, updated_at
  ) VALUES (
    '0deadbee-f000-0000-0000-000000000001',
    v_sport_id,
    'Sortie découverte Junto',
    'Activité de démonstration pour découvrir l''app. Libre à toi d''y jeter un œil !',
    'débutant',
    10,
    ST_SetSRID(ST_MakePoint(p_lng + v_offset_lng, p_lat + v_offset_lat), 4326)::geography,
    now() + INTERVAL '3 days',
    '2 hours'::interval,
    'public',
    'published',
    now(), now()
  ) RETURNING id INTO v_activity_id;

  INSERT INTO participations (activity_id, user_id, status, created_at)
  VALUES (v_activity_id, '0deadbee-f000-0000-0000-000000000001', 'accepted', now());

  RETURN v_activity_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION seed_demo_activity FROM anon;
GRANT EXECUTE ON FUNCTION seed_demo_activity TO authenticated;
