-- ============================================================================
-- 00480 — Phase B2 : résidus de la contre-vérification de la phase B.
--
-- private.rate_hit(kind, limit, window) : compteur de fréquence commun, compté
--   par ÉVÉNEMENT (jamais par lignes restantes), sous verrou consultatif.
-- AB-10 Le matériel envoyait un signal par LIGNE (une mise à jour de 50 objets
--   = 150 signaux) et sans limite → déclencheurs par INSTRUCTION (un signal par
--   sortie et par instruction) + 20 mises à jour de matériel / min / compte,
--   30 / min pour les objets manquants.
-- AB-2 / AC-10 / DC-3  update_activity 30 / h, update_activity_trace 20 / h,
--   compute_trace_stats 120 / h par compte.
-- AC-1 L'écriture directe sur `activities` contournait tout cela (et les
--   contrôles de update_activity) : UPDATE retiré aux clients, policy supprimée.
--   L'app n'écrit jamais directement (vérifié).
-- Signal carte : colonnes manquantes ajoutées (lieu d'arrivée, noms de lieu,
--   distance, D+, présence d'une trace, présence exigée) + passage en démo ;
--   verrou de limitation pris seulement quand la fenêtre est écoulée ; table
--   map_broadcasts sans journal et purgée chaque jour.
-- Traces partagées : budget de 5 Mo / 24 h, erreur `junto.trace_too_large`.
-- ============================================================================

CREATE TABLE IF NOT EXISTS rate_events (
  user_id UUID NOT NULL,
  kind TEXT NOT NULL CHECK (char_length(kind) BETWEEN 1 AND 40),
  at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS rate_events_user_kind_at_idx ON rate_events (user_id, kind, at DESC);
ALTER TABLE rate_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE rate_events FORCE ROW LEVEL SECURITY;
REVOKE ALL ON rate_events FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.rate_hit(p_kind text, p_limit integer, p_window interval)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user UUID := auth.uid();
  v_count INTEGER;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  PERFORM pg_advisory_xact_lock(hashtext(v_user::text || '_rate_' || p_kind));
  SELECT count(*) INTO v_count FROM rate_events
  WHERE user_id = v_user AND kind = p_kind AND at > now() - p_window;
  IF v_count >= p_limit THEN RAISE EXCEPTION 'junto.too_many_actions'; END IF;
  INSERT INTO rate_events (user_id, kind) VALUES (v_user, p_kind);
END;
$function$;
REVOKE ALL ON FUNCTION private.rate_hit(text, integer, interval) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.set_activity_gear(p_activity_id uuid, p_items jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_item JSONB;
  v_name TEXT;
  v_qty INTEGER;
  v_is_shared BOOLEAN;
  v_catalog_is_shared BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00480: frequency cap (audit, counter-review of phase B).
  PERFORM private.rate_hit('gear', 20, INTERVAL '1 minute');

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = p_activity_id
      AND status IN ('published', 'in_progress')
      AND starts_at > NOW() - INTERVAL '15 seconds'
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- H7: cap the array size so a megabyte-sized payload can't blow up
  -- the loop. 50 items is generous for legit use.
  IF jsonb_array_length(p_items) > 50 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  DELETE FROM activity_gear WHERE activity_id = p_activity_id AND user_id = v_user_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    -- H5c: strip HTML/script tags before storing the user-provided
    -- gear name (catalog items are stored as keys and immune).
    v_name := regexp_replace(trim(v_item->>'name'), '<[^>]*>', '', 'g');
    v_qty := COALESCE((v_item->>'quantity')::integer, 1);

    IF v_name IS NOT NULL AND char_length(v_name) > 0 AND v_qty > 0 THEN
      v_qty := LEAST(v_qty, 99);

      SELECT is_shared INTO v_catalog_is_shared
      FROM gear_catalog WHERE name_key = v_name LIMIT 1;
      v_is_shared := COALESCE(v_catalog_is_shared, (v_item->>'is_shared')::boolean, false);

      INSERT INTO activity_gear (activity_id, user_id, gear_name, quantity, is_shared)
      VALUES (p_activity_id, v_user_id, v_name, v_qty, v_is_shared);
    END IF;
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.add_missing_gear(p_activity_id uuid, p_name text, p_quantity integer DEFAULT 1)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_name TEXT;
  v_qty INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00480: frequency cap (audit, counter-review of phase B).
  PERFORM private.rate_hit('gear_missing', 30, INTERVAL '1 minute');

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = p_activity_id
      AND status IN ('published', 'in_progress')
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) AND NOT EXISTS (
    SELECT 1 FROM activities WHERE id = p_activity_id AND creator_id = v_user_id
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Same HTML-strip as set_activity_gear (00238 H5c).
  v_name := regexp_replace(trim(coalesce(p_name, '')), '<[^>]*>', '', 'g');
  IF char_length(v_name) < 1 OR char_length(v_name) > 60 THEN
    RAISE EXCEPTION 'junto.gear_invalid';
  END IF;
  v_qty := GREATEST(1, LEAST(coalesce(p_quantity, 1), 99));

  -- Anti-noise cap.
  IF (SELECT count(*) FROM activity_gear_missing WHERE activity_id = p_activity_id) >= 20 THEN
    RAISE EXCEPTION 'junto.gear_missing_limit';
  END IF;

  INSERT INTO activity_gear_missing (activity_id, name, quantity, created_by)
  VALUES (p_activity_id, v_name, v_qty, v_user_id)
  ON CONFLICT (activity_id, lower(name))
  DO UPDATE SET quantity = EXCLUDED.quantity;
END;
$function$;

CREATE OR REPLACE FUNCTION public.remove_missing_gear(p_activity_id uuid, p_name text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00480: frequency cap (audit, counter-review of phase B).
  PERFORM private.rate_hit('gear_missing', 30, INTERVAL '1 minute');

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = p_activity_id
      AND status IN ('published', 'in_progress')
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) AND NOT EXISTS (
    SELECT 1 FROM activities WHERE id = p_activity_id AND creator_id = v_user_id
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  DELETE FROM activity_gear_missing
  WHERE activity_id = p_activity_id
    AND lower(name) = lower(trim(coalesce(p_name, '')));
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_activity(p_activity_id uuid, p_title text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_level text DEFAULT NULL::text, p_max_participants integer DEFAULT NULL::integer, p_meeting_lng double precision DEFAULT NULL::double precision, p_meeting_lat double precision DEFAULT NULL::double precision, p_starts_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_duration text DEFAULT NULL::text, p_visibility text DEFAULT NULL::text, p_level_max text DEFAULT NULL::text, p_meeting_locality text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_old RECORD;
  v_new RECORD;
  v_participant RECORD;
  v_trimmed_title TEXT;
  v_level_max TEXT;
  v_changes JSONB;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00480: frequency cap (audit, counter-review of phase B).
  PERFORM private.rate_hit('activity_update', 30, INTERVAL '1 hour');

  IF p_title IS NOT NULL THEN
    v_trimmed_title := trim(p_title);
    IF char_length(v_trimmed_title) < 3 THEN RAISE EXCEPTION 'junto.title_too_short'; END IF;
  END IF;

  -- Normalised range high end (only applied when the level is being edited).
  v_level_max := NULLIF(trim(coalesce(p_level_max, '')), '');
  IF p_level IS NOT NULL AND v_level_max = trim(p_level) THEN v_level_max := NULL; END IF;

  SELECT id, creator_id, status, title, description, starts_at, duration,
         location_meeting, max_participants, level, visibility
  INTO v_old FROM activities WHERE id = p_activity_id FOR UPDATE;

  IF v_old IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_old.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_old.status NOT IN ('published', 'in_progress') THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- The client resends starts_at as an ISO string (millisecond precision)
  -- while Postgres stores microseconds — a raw IS DISTINCT FROM would see a
  -- sub-millisecond ghost diff on any row whose date has non-zero µs (seed,
  -- manual INSERTs) and re-trigger the date_in_past bug plus phantom
  -- "activity updated" notifs. Normalise: an unchanged-at-ms-precision date
  -- is treated as "not provided" for everything downstream (validation,
  -- UPDATE, change diff).
  IF p_starts_at IS NOT NULL
     AND date_trunc('milliseconds', p_starts_at) IS NOT DISTINCT FROM date_trunc('milliseconds', v_old.starts_at) THEN
    p_starts_at := NULL;
  END IF;

  -- Only validate the date when it actually changes — resending the
  -- unchanged (now past) starts_at of an in-progress activity is not a
  -- reschedule and must not block editing the other fields.
  IF p_starts_at IS NOT NULL THEN
    IF p_starts_at <= NOW() THEN
      RAISE EXCEPTION 'junto.date_in_past';
    END IF;
    IF p_starts_at > NOW() + INTERVAL '6 months' THEN
      RAISE EXCEPTION 'junto.date_too_far';
    END IF;
  END IF;

  -- p_max_participants = 0 is the explicit "make it open" sentinel (NULL
  -- means "unchanged", so it can't express open — the edit screen's open
  -- toggle silently did nothing before this). 0 sits outside the valid
  -- [2,50] range so it can't collide with a real cap. Any other
  -- out-of-range value is rejected (parity with create_activity — before
  -- this it surfaced as a raw table CHECK violation).
  IF p_max_participants IS NOT NULL AND p_max_participants != 0
     AND (p_max_participants < 2 OR p_max_participants > 50) THEN
    RAISE EXCEPTION 'junto.participants_range';
  END IF;

  -- Tamper guard (UI only sends valid values): generic. Parity with create_activity.
  IF p_visibility IS NOT NULL
     AND p_visibility NOT IN ('public', 'approval', 'private_link', 'private_link_approval') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Private-link visibilities open to all (Scott 2026-07-10) — no gate.

  UPDATE activities SET
    title = COALESCE(v_trimmed_title, title),
    description = CASE WHEN p_description IS NOT NULL THEN trim(p_description) ELSE description END,
    level = COALESCE(p_level, level),
    level_max = CASE WHEN p_level IS NOT NULL THEN v_level_max ELSE level_max END,
    max_participants = CASE
      WHEN p_max_participants = 0 THEN NULL
      WHEN p_max_participants IS NOT NULL THEN p_max_participants
      ELSE max_participants END,
    location_meeting = CASE
      WHEN p_meeting_lng IS NOT NULL AND p_meeting_lat IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_meeting_lng, p_meeting_lat), 4326)::geography
      ELSE location_meeting END,
    -- Only alongside a pin move (00441); the trigger freezes it otherwise.
    meeting_locality = CASE
      WHEN p_meeting_lng IS NOT NULL AND p_meeting_lat IS NOT NULL
      THEN CASE WHEN p_meeting_locality IS NOT NULL AND char_length(trim(p_meeting_locality)) > 0
                THEN left(trim(p_meeting_locality), 80) ELSE NULL END
      ELSE meeting_locality END,
    starts_at = COALESCE(p_starts_at, starts_at),
    duration = CASE WHEN p_duration IS NOT NULL THEN p_duration::interval ELSE duration END,
    visibility = COALESCE(p_visibility, visibility)
  WHERE id = p_activity_id;

  -- Re-fetch after the UPDATE (whitelist trigger may have forced privileged
  -- columns back to OLD when participants exist — only notify on real changes).
  SELECT title, description, starts_at, duration, location_meeting,
         max_participants, level, visibility
  INTO v_new FROM activities WHERE id = p_activity_id;

  v_changes := '{}'::jsonb;
  IF v_old.title IS DISTINCT FROM v_new.title THEN
    v_changes := v_changes || jsonb_build_object('title', true);
  END IF;
  IF v_old.starts_at IS DISTINCT FROM v_new.starts_at THEN
    v_changes := v_changes || jsonb_build_object('starts_at', true);
  END IF;
  IF v_old.duration IS DISTINCT FROM v_new.duration THEN
    v_changes := v_changes || jsonb_build_object('duration', true);
  END IF;
  IF v_old.location_meeting IS DISTINCT FROM v_new.location_meeting THEN
    v_changes := v_changes || jsonb_build_object('location_meeting', true);
  END IF;
  IF v_old.description IS DISTINCT FROM v_new.description THEN
    v_changes := v_changes || jsonb_build_object('description', true);
  END IF;
  IF v_old.level IS DISTINCT FROM v_new.level THEN
    v_changes := v_changes || jsonb_build_object('level', true);
  END IF;
  IF v_old.max_participants IS DISTINCT FROM v_new.max_participants THEN
    v_changes := v_changes || jsonb_build_object('max_participants', true);
  END IF;
  IF v_old.visibility IS DISTINCT FROM v_new.visibility THEN
    v_changes := v_changes || jsonb_build_object('visibility', true);
  END IF;

  -- No real change happened (every requested field was rejected by trigger or unchanged) — skip notif
  IF v_changes = '{}'::jsonb THEN RETURN; END IF;

  FOR v_participant IN
    SELECT user_id FROM participations
    WHERE activity_id = p_activity_id AND status = 'accepted' AND user_id != v_user_id
  LOOP
    PERFORM create_notification(
      v_participant.user_id,
      'activity_updated',
      'Sortie modifiée',
      '« ' || v_new.title || ' » a changé — vérifie l''heure et le rendez-vous.',
      jsonb_build_object('activity_id', p_activity_id, 'changes', v_changes,
        'params', jsonb_build_object('title', v_new.title))
    );
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_activity_trace(p_activity_id uuid, p_trace_geojson jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_old_trace JSONB;
  v_title TEXT;
  v_participant RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00480: frequency cap (audit, counter-review of phase B).
  PERFORM private.rate_hit('activity_trace', 20, INTERVAL '1 hour');

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = p_activity_id
      AND creator_id = v_user_id
      AND status IN ('published', 'in_progress')
      AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00470 (audit M6): same gate as create_activity.
  IF p_trace_geojson IS NOT NULL AND NOT trace_geojson_ok(p_trace_geojson) THEN
    RAISE EXCEPTION 'junto.trace_geojson_invalid';
  END IF;

  SELECT trace_geojson, title INTO v_old_trace, v_title FROM activities WHERE id = p_activity_id;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  UPDATE activities
  SET trace_geojson = p_trace_geojson,
      distance_km = CASE
        WHEN p_trace_geojson IS NOT NULL AND distance_km IS NULL
          THEN (SELECT CASE WHEN round(d, 1) > 0 AND d <= 9999 THEN d END FROM (SELECT trace_distance_km(p_trace_geojson) AS d) x)
        ELSE distance_km END,
      elevation_gain_m = CASE
        WHEN p_trace_geojson IS NOT NULL AND elevation_gain_m IS NULL
          THEN (SELECT CASE WHEN g > 0 AND g <= 99999 THEN g END FROM (SELECT trace_elevation_gain_m(p_trace_geojson) AS g) x)
        ELSE elevation_gain_m END,
      updated_at = now()
  WHERE id = p_activity_id;
  PERFORM set_config('junto.bypass_lock', 'false', true);

  -- 00475 (audit L9, Scott 2026-10-21): the route is part of what people
  -- signed up for — a changed trace notifies the accepted participants, like
  -- an hour or meeting-point change does in update_activity.
  IF v_old_trace IS DISTINCT FROM p_trace_geojson THEN
    FOR v_participant IN
      SELECT user_id FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted' AND user_id != v_user_id
    LOOP
      PERFORM create_notification(
        v_participant.user_id,
        'activity_updated',
        'Itinéraire modifié',
        '« ' || v_title || ' » a un nouvel itinéraire — jette un œil à la trace.',
        jsonb_build_object('activity_id', p_activity_id,
          'changes', jsonb_build_object('trace', true),
          'variant', 'trace',
          'params', jsonb_build_object('title', v_title))
      );
    END LOOP;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.compute_trace_stats(p_geojson jsonb)
 RETURNS TABLE(distance_km numeric, elevation_gain_m integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_geom geometry;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00480: frequency cap (audit, counter-review of phase B).
  PERFORM private.rate_hit('trace_stats', 120, INTERVAL '1 hour');

  -- 00470 (audit L7): cheap shape/size gate before the PostGIS parse.
  IF p_geojson IS NULL OR NOT trace_geojson_ok(p_geojson) THEN
    RAISE EXCEPTION 'junto.trace_geojson_invalid';
  END IF;

  BEGIN
    v_geom := ST_GeomFromGeoJSON(p_geojson::text);
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'junto.trace_geojson_invalid';
  END;
  IF ST_GeometryType(v_geom) <> 'ST_LineString'
     OR ST_NPoints(v_geom) < 2
     OR ST_NPoints(v_geom) > 10000 THEN
    RAISE EXCEPTION 'junto.trace_geojson_invalid';
  END IF;

  RETURN QUERY SELECT trace_distance_km(p_geojson), trace_elevation_gain_m(p_geojson);
END;
$function$;

CREATE OR REPLACE FUNCTION public.broadcast_map_activity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.visibility IN ('public', 'approval') AND NOT OLD.is_demo THEN PERFORM map_ping(OLD.id); END IF;
    RETURN NULL;
  END IF;
  -- A public outing switched to demo must disappear from maps: ping on the flip.
  IF TG_OP = 'UPDATE' AND NEW.is_demo IS DISTINCT FROM OLD.is_demo THEN PERFORM map_ping(NEW.id); RETURN NULL; END IF;
  IF NEW.is_demo THEN RETURN NULL; END IF;
  IF NOT (NEW.visibility IN ('public', 'approval')
          OR (TG_OP = 'UPDATE' AND OLD.visibility IN ('public', 'approval'))) THEN
    RETURN NULL;
  END IF;
  IF TG_OP = 'UPDATE' AND NOT (
       NEW.status IS DISTINCT FROM OLD.status
    OR NEW.starts_at IS DISTINCT FROM OLD.starts_at
    OR NEW.duration IS DISTINCT FROM OLD.duration
    OR NEW.location_meeting IS DISTINCT FROM OLD.location_meeting
    OR NEW.location_objective IS DISTINCT FROM OLD.location_objective
    OR NEW.title IS DISTINCT FROM OLD.title
    OR NEW.max_participants IS DISTINCT FROM OLD.max_participants
    OR NEW.visibility IS DISTINCT FROM OLD.visibility
    OR NEW.deleted_at IS DISTINCT FROM OLD.deleted_at
    OR NEW.level IS DISTINCT FROM OLD.level
    OR NEW.level_max IS DISTINCT FROM OLD.level_max
    OR NEW.sport_id IS DISTINCT FROM OLD.sport_id
    -- 00480: every column the map payload shows (getNearby / activities_with_coords).
    OR NEW.location_end IS DISTINCT FROM OLD.location_end
    OR NEW.meeting_name IS DISTINCT FROM OLD.meeting_name
    OR NEW.meeting_locality IS DISTINCT FROM OLD.meeting_locality
    OR NEW.objective_name IS DISTINCT FROM OLD.objective_name
    OR NEW.distance_km IS DISTINCT FROM OLD.distance_km
    OR NEW.elevation_gain_m IS DISTINCT FROM OLD.elevation_gain_m
    OR (NEW.trace_geojson IS NULL) IS DISTINCT FROM (OLD.trace_geojson IS NULL)
    OR NEW.requires_presence IS DISTINCT FROM OLD.requires_presence
  ) THEN
    RETURN NULL;
  END IF;
  PERFORM map_ping(NEW.id);
  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.map_ping(p_activity_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_sent INT;
BEGIN
  -- Throttle: at most one signal per outing every 15 s. UPDATE first so the
  -- row is locked only when the window has elapsed (00480 — the previous
  -- INSERT … ON CONFLICT … WHERE locked it on every write, a new deadlock
  -- coupling between unrelated transactions).
  UPDATE map_broadcasts SET at = now()
  WHERE activity_id = p_activity_id AND at < now() - INTERVAL '15 seconds';
  GET DIAGNOSTICS v_sent = ROW_COUNT;
  IF v_sent = 0 THEN
    INSERT INTO map_broadcasts (activity_id, at) VALUES (p_activity_id, now())
    ON CONFLICT (activity_id) DO NOTHING;
    GET DIAGNOSTICS v_sent = ROW_COUNT;
  END IF;
  IF v_sent = 0 THEN RETURN; END IF;
  BEGIN
    PERFORM realtime.send('{}'::jsonb, 'map', 'map', true);
  EXCEPTION WHEN OTHERS THEN NULL; -- never fail the user's write for a ping
  END;
END;
$function$;

CREATE OR REPLACE FUNCTION public.share_trace_message(p_conversation_id uuid, p_trace_geojson jsonb, p_name text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_coord_count INTEGER;
  v_clean_name TEXT;
  v_recent INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM private.assert_can_send(p_conversation_id, v_user_id);

  IF p_trace_geojson IS NULL
     OR p_trace_geojson->>'type' != 'LineString'
     OR jsonb_typeof(p_trace_geojson->'coordinates') != 'array' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  v_coord_count := jsonb_array_length(p_trace_geojson->'coordinates');
  IF v_coord_count < 2 OR v_coord_count > 10000 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- Schema + NUMERIC BOUNDS (design review: 1e300 coords sailed straight into
  -- the map renderer). lon/lat ranges, plausible elevation.
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_trace_geojson->'coordinates') AS coord
    WHERE jsonb_typeof(coord) != 'array'
       OR jsonb_array_length(coord) < 2
       OR jsonb_array_length(coord) > 3
       OR jsonb_typeof(coord->0) != 'number'
       OR jsonb_typeof(coord->1) != 'number'
       OR (coord->>0)::numeric < -180 OR (coord->>0)::numeric > 180
       OR (coord->>1)::numeric < -90 OR (coord->>1)::numeric > 90
       OR (jsonb_array_length(coord) = 3 AND (
            jsonb_typeof(coord->2) != 'number'
            OR (coord->>2)::numeric < -500 OR (coord->>2)::numeric > 9000
       ))
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_name := CASE
    WHEN p_name IS NOT NULL AND char_length(trim(p_name)) > 0
    THEN substring(regexp_replace(trim(p_name), '<[^>]*>', '', 'g') from 1 for 100)
    ELSE 'trace.gpx'
  END;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_share_trace'));
  SELECT count(*) INTO v_recent FROM messages
  WHERE sender_id = v_user_id AND metadata->>'type' = 'shared_trace'
    AND created_at > now() - INTERVAL '1 minute';
  IF v_recent >= 1 THEN RAISE EXCEPTION 'junto.share_rate_limit'; END IF;
  -- 00479 (AB-3 / MS-7): daily cap and total size bound (≤ 1 MB, the shared
  -- trace gate used by activities) — numbers of arbitrary precision made
  -- multi-MB messages possible.
  SELECT count(*) INTO v_recent FROM messages
  WHERE sender_id = v_user_id AND metadata->>'type' = 'shared_trace'
    AND created_at > now() - INTERVAL '24 hours';
  IF v_recent >= 20 THEN RAISE EXCEPTION 'junto.share_daily_cap'; END IF;
  IF pg_column_size(p_trace_geojson) > 1000000 THEN RAISE EXCEPTION 'junto.trace_too_large'; END IF;
  IF NOT trace_geojson_ok(p_trace_geojson) THEN RAISE EXCEPTION 'junto.trace_geojson_invalid'; END IF;
  -- 00480: byte budget too (20 × 1 MB a day per account was still a lot).
  IF (SELECT coalesce(sum(pg_column_size(metadata)), 0) FROM messages
      WHERE sender_id = v_user_id AND metadata->>'type' = 'shared_trace'
        AND created_at > now() - INTERVAL '24 hours') + pg_column_size(p_trace_geojson) > 5000000 THEN
    RAISE EXCEPTION 'junto.share_daily_cap';
  END IF;

  RETURN private.insert_rich_message(
    p_conversation_id, v_user_id,
    '🗺️ ' || v_clean_name,
    jsonb_build_object('type', 'shared_trace', 'name', v_clean_name, 'trace_geojson', p_trace_geojson)
  );
END;
$function$;

-- ---------- AB-10 : un signal par instruction ----------
CREATE OR REPLACE FUNCTION public.broadcast_activity_change_stmt()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_activity UUID;
BEGIN
  -- Transition tables only exist for the events that define them: branch on
  -- TG_OP so an INSERT trigger never references old_rows (and vice versa).
  FOR v_activity IN EXECUTE CASE TG_OP
      WHEN 'INSERT' THEN 'SELECT DISTINCT activity_id FROM new_rows WHERE activity_id IS NOT NULL'
      WHEN 'DELETE' THEN 'SELECT DISTINCT activity_id FROM old_rows WHERE activity_id IS NOT NULL'
      ELSE 'SELECT activity_id FROM new_rows WHERE activity_id IS NOT NULL UNION SELECT activity_id FROM old_rows WHERE activity_id IS NOT NULL'
    END
  LOOP
    BEGIN
      PERFORM realtime.send(jsonb_build_object('table', TG_TABLE_NAME, 'op', TG_OP), 'change', 'activity:' || v_activity::text, true);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
  RETURN NULL;
END;
$function$;
REVOKE ALL ON FUNCTION public.broadcast_activity_change_stmt() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_activity_gear_broadcast ON activity_gear;
CREATE TRIGGER trg_activity_gear_bc_ins AFTER INSERT ON activity_gear REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION broadcast_activity_change_stmt();
CREATE TRIGGER trg_activity_gear_bc_upd AFTER UPDATE ON activity_gear REFERENCING NEW TABLE AS new_rows OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION broadcast_activity_change_stmt();
CREATE TRIGGER trg_activity_gear_bc_del AFTER DELETE ON activity_gear REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION broadcast_activity_change_stmt();

DROP TRIGGER IF EXISTS trg_activity_gear_missing_broadcast ON activity_gear_missing;
CREATE TRIGGER trg_activity_gear_missing_bc_ins AFTER INSERT ON activity_gear_missing REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION broadcast_activity_change_stmt();
CREATE TRIGGER trg_activity_gear_missing_bc_upd AFTER UPDATE ON activity_gear_missing REFERENCING NEW TABLE AS new_rows OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION broadcast_activity_change_stmt();
CREATE TRIGGER trg_activity_gear_missing_bc_del AFTER DELETE ON activity_gear_missing REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION broadcast_activity_change_stmt();


-- ---------- AC-1 : plus d'écriture directe sur activities ----------
DROP POLICY IF EXISTS activities_update_creator ON activities;
REVOKE UPDATE ON activities FROM authenticated, anon;

-- ---------- Hygiène des tables de limitation ----------
ALTER TABLE map_broadcasts SET UNLOGGED;
CREATE OR REPLACE FUNCTION purge_throttle_tables()
RETURNS VOID LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  DELETE FROM map_broadcasts WHERE at < now() - INTERVAL '1 day';
  DELETE FROM rate_events WHERE at < now() - INTERVAL '2 days';
$$;
REVOKE ALL ON FUNCTION purge_throttle_tables() FROM PUBLIC, anon, authenticated;
SELECT cron.unschedule('junto-throttle-purge') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'junto-throttle-purge');
SELECT cron.schedule('junto-throttle-purge', '45 4 * * *', 'SELECT public.purge_throttle_tables();');
