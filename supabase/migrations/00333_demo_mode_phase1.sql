-- ============================================================================
-- 00333 — Demo mode, PHASE 1 (mechanism only, activities)
--
-- An admin toggle that reveals a set of pre-built demo content on the map so
-- Scott can present the app live (to pros / prospects) in one tap. Phase 1
-- proves the whole chain on ACTIVITIES; pros + offerings + rich content come in
-- Phase 2.
--
-- Model (Scott 2026-07-21): "curtain" — demo rows persist but hidden, a global
-- flag flips their visibility, and only ADMINS ever see them (testers/anon
-- never do). On enable, demo activity dates are auto-refreshed to upcoming, so
-- the toggle works standalone months later with nobody behind a computer.
-- ============================================================================

-- 1) Privileged marker on the entities. Admin-only (whitelist-protected below).
ALTER TABLE users      ADD COLUMN IF NOT EXISTS is_demo boolean NOT NULL DEFAULT false;
ALTER TABLE activities ADD COLUMN IF NOT EXISTS is_demo boolean NOT NULL DEFAULT false;

-- 2) Whitelist protection — reproduce the two update triggers + force is_demo to
--    OLD (so no client can flag/unflag demo content; only bypass_lock functions).
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

  NEW.id := OLD.id;
  NEW.email := OLD.email;
  NEW.created_at := OLD.created_at;
  NEW.age_confirmed_at := OLD.age_confirmed_at;
  NEW.tier := OLD.tier;
  NEW.is_pro_verified := OLD.is_pro_verified;
  NEW.pro_verified_at := OLD.pro_verified_at;
  NEW.is_admin := OLD.is_admin;
  NEW.is_demo := OLD.is_demo;
  NEW.suspended_at := OLD.suspended_at;
  NEW.accepted_tos_at := OLD.accepted_tos_at;
  NEW.accepted_privacy_at := OLD.accepted_privacy_at;
  NEW.tutorial_seen_at := OLD.tutorial_seen_at;
  NEW.push_token := OLD.push_token;
  NEW.reliability_score := OLD.reliability_score;
  NEW.levels_per_sport := OLD.levels_per_sport;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

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
  NEW.deleted_at := OLD.deleted_at;
  NEW.cancelled_reason := OLD.cancelled_reason;
  NEW.distance_km := OLD.distance_km;
  NEW.elevation_gain_m := OLD.elevation_gain_m;
  NEW.meeting_name := OLD.meeting_name;
  NEW.trace_geojson := OLD.trace_geojson;
  NEW.route := OLD.route;
  NEW.is_demo := OLD.is_demo;

  IF (SELECT count(*) FROM participations
      WHERE activity_id = NEW.id AND status = 'accepted' AND user_id != OLD.creator_id) > 0
  THEN
    NEW.location_meeting := OLD.location_meeting;
    NEW.location_end := OLD.location_end;
    NEW.location_objective := OLD.location_objective;
    NEW.objective_name := OLD.objective_name;
    NEW.starts_at := OLD.starts_at;
    NEW.level := OLD.level;
    NEW.level_max := OLD.level_max;
    NEW.max_participants := OLD.max_participants;
    NEW.visibility := OLD.visibility;
    NEW.requires_presence := OLD.requires_presence;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- 3) Global flag (key/value app_config).
INSERT INTO app_config (name, value) VALUES ('demo_mode', 'false')
ON CONFLICT DO NOTHING;

-- 4) Visibility predicate: demo content shows ONLY when the flag is on AND the
--    caller is a (non-suspended) admin. Anon/testers → false → never see demo.
CREATE OR REPLACE FUNCTION demo_content_visible()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT
    coalesce((SELECT value = 'true' FROM app_config WHERE name = 'demo_mode'), false)
    AND EXISTS (
      SELECT 1 FROM users
      WHERE id = auth.uid() AND is_admin = true AND suspended_at IS NULL
    );
$$;
GRANT EXECUTE ON FUNCTION demo_content_visible() TO anon, authenticated;

-- 5) Map view gains the demo gate (reproduced from 00315 + one AND clause).
CREATE OR REPLACE VIEW activities_with_coords AS
SELECT
  a.id, a.creator_id, a.sport_id, a.title, a.description, a.level,
  a.distance_km, a.elevation_gain_m,
  a.max_participants, a.starts_at, a.duration, a.visibility,
  a.requires_presence,
  a.status, a.deleted_at, a.created_at, a.updated_at,
  a.objective_name, a.meeting_name,
  a.trace_geojson,
  ST_X(COALESCE(a.location_objective, a.location_meeting)::geometry) AS lng,
  ST_Y(COALESCE(a.location_objective, a.location_meeting)::geometry) AS lat,
  ST_X(a.location_meeting::geometry) AS meeting_lng,
  ST_Y(a.location_meeting::geometry) AS meeting_lat,
  ST_X(a.location_end::geometry) AS end_lng,
  ST_Y(a.location_end::geometry) AS end_lat,
  ST_X(a.location_objective::geometry) AS objective_lng,
  ST_Y(a.location_objective::geometry) AS objective_lat,
  pp.display_name AS creator_name,
  pp.avatar_url AS creator_avatar,
  s.key AS sport_key,
  s.icon AS sport_icon,
  s.category AS sport_category,
  (SELECT count(*)::int FROM participations p
   WHERE p.activity_id = a.id AND p.status = 'accepted') AS participant_count,
  a.level_max
FROM activities a
JOIN public_profiles pp ON a.creator_id = pp.id
JOIN sports s ON a.sport_id = s.id
WHERE a.deleted_at IS NULL
  AND a.status IN ('published', 'in_progress')
  AND (a.is_demo = false OR demo_content_visible())
  AND (
    a.visibility IN ('public', 'approval')
    OR (
      a.visibility IN ('private_link', 'private_link_approval')
      AND (
        a.creator_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM participations p2
          WHERE p2.activity_id = a.id
            AND p2.user_id = auth.uid()
            AND p2.status = 'accepted'
        )
      )
    )
  )
  AND NOT private.user_is_suspended(a.creator_id)
  AND a.creator_id NOT IN (
    SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid()
  );

-- 6) The toggle. Admin-gated; on enable, refresh demo dates so they're always
--    upcoming (runs server-side on the tap — no manual step, ever).
CREATE OR REPLACE FUNCTION admin_set_demo_mode(p_on boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin uuid;
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM users WHERE id = v_admin AND is_admin = true AND suspended_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE app_config SET value = CASE WHEN p_on THEN 'true' ELSE 'false' END
  WHERE name = 'demo_mode';

  IF p_on THEN
    PERFORM set_config('junto.bypass_lock', 'true', true);
    WITH ordered AS (
      SELECT id, row_number() OVER (ORDER BY created_at, id) AS rn
      FROM activities WHERE is_demo = true AND deleted_at IS NULL
    )
    UPDATE activities a
    SET starts_at = date_trunc('day', now()) + (o.rn * INTERVAL '2 days') + INTERVAL '9 hours',
        status = 'published'
    FROM ordered o
    WHERE a.id = o.id;
  END IF;

  PERFORM log_admin_action(
    v_admin,
    CASE WHEN p_on THEN 'demo_mode_on' ELSE 'demo_mode_off' END,
    'app_config', NULL, NULL, NULL
  );
END;
$$;
REVOKE ALL ON FUNCTION admin_set_demo_mode(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_set_demo_mode(boolean) TO authenticated;

-- 7) Seed 2 demo activities (owner = bobby, the bootstrap admin). Phase 2 will
--    add dedicated demo accounts + rich content (gear, transport, traces…).
DO $$
DECLARE
  v_owner uuid;
  v_hike uuid;
  v_climb uuid;
BEGIN
  SELECT id INTO v_owner FROM public.users WHERE lower(email) = lower('bobbybobard0@gmail.com');
  IF v_owner IS NULL THEN
    RAISE EXCEPTION '[00333] demo owner bobbybobard0@gmail.com NOT FOUND';
  END IF;
  SELECT id INTO v_hike  FROM sports WHERE key = 'hiking';
  SELECT id INTO v_climb FROM sports WHERE key = 'climbing-sport';

  PERFORM set_config('junto.bypass_lock', 'true', true);
  INSERT INTO activities
    (creator_id, sport_id, title, description, level, max_participants,
     location_meeting, meeting_name, starts_at, duration, visibility,
     requires_presence, status, is_demo)
  VALUES
    (v_owner, v_hike, 'Rando au lac de l''Orceyrette',
     'Belle boucle au départ de Briançon, vue sur les Écrins. Rythme tranquille, ouverte à tous.',
     'intermédiaire', 8,
     ST_SetSRID(ST_MakePoint(6.6626, 44.9003), 4326)::geography, 'Parking de l''Orceyrette',
     now() + INTERVAL '2 days', INTERVAL '4 hours', 'public', false, 'published', true),
    (v_owner, v_climb, 'Grande voie au Rocher Baron',
     'Plusieurs longueurs en 5c-6a, ambiance montagne. Cordée de 4 max, matériel à prévoir.',
     'avancé', 4,
     ST_SetSRID(ST_MakePoint(6.6100, 44.8600), 4326)::geography, 'Pied du Rocher Baron',
     now() + INTERVAL '4 days', INTERVAL '5 hours', 'public', false, 'published', true);
END $$;
