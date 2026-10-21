-- ============================================================================
-- 00470 — Audit octobre 2026, phase 3 : traces (docs/AUDIT_2026-10.md M5, M6,
-- L7, L10). Base = définitions vivantes (00452 / 00453).
--
-- M6  trace_geojson_ok() : garde unique de forme et de taille — LineString,
--     2..10000 points, chaque point = tableau de 2 à 4 éléments, lng/lat
--     numériques dans leurs bornes, altitude/temps numériques bornés ou null,
--     ≤ 1 Mo. Appliquée par create_activity, update_activity_trace et
--     compute_trace_stats AVANT tout calcul. Une trace « [null,null] » ne
--     passe plus (elle faisait planter la fiche chez les lecteurs).
-- M5  Distance / D+ déduits hors des bornes de la colonne (trace plate ou
--     descendante → 0 m, trace dégénérée, distance absurde) restent NULL au
--     lieu de faire échouer la création ou la pose de trace.
-- L7  create_activity : calcul de la trace déplacé après les plafonds jour/mois.
-- L10 trace_elevation_gain_m : une altitude hors de ±100 000 m est ignorée au
--     lieu de déborder en double precision (erreur brute au client).
-- Les helpers gardent leur sémantique (0 m reste 0 pour la bibliothèque GPX).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.trace_geojson_ok(p_geojson jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT p_geojson IS NOT NULL
    AND pg_column_size(p_geojson) <= 1000000
    AND jsonb_typeof(p_geojson) = 'object'
    AND p_geojson->>'type' = 'LineString'
    AND jsonb_typeof(p_geojson->'coordinates') = 'array'
    AND jsonb_array_length(p_geojson->'coordinates') BETWEEN 2 AND 10000
    AND NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(p_geojson->'coordinates') AS c
      WHERE jsonb_typeof(c) <> 'array'
         OR jsonb_array_length(c) NOT BETWEEN 2 AND 4
         OR jsonb_typeof(c->0) <> 'number' OR jsonb_typeof(c->1) <> 'number'
         OR abs((c->>0)::numeric) > 180 OR abs((c->>1)::numeric) > 90
         OR (jsonb_array_length(c) >= 3 AND jsonb_typeof(c->2) NOT IN ('number', 'null'))
         OR (jsonb_array_length(c) >= 3 AND jsonb_typeof(c->2) = 'number' AND abs((c->>2)::numeric) > 100000)
         OR (jsonb_array_length(c) = 4 AND jsonb_typeof(c->3) NOT IN ('number', 'null'))
         OR (jsonb_array_length(c) = 4 AND jsonb_typeof(c->3) = 'number' AND abs((c->>3)::numeric) > 1e13)
    );
$function$;
REVOKE ALL ON FUNCTION public.trace_geojson_ok(jsonb) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.trace_elevation_gain_m(p_geojson jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 IMMUTABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  c_threshold CONSTANT DOUBLE PRECISION := 5;
  v_raw DOUBLE PRECISION[];
  v_z DOUBLE PRECISION[];
  v_smooth DOUBLE PRECISION[];
  v_n INTEGER;
  v_with_z INTEGER;
  v_ref DOUBLE PRECISION;
  v_gain DOUBLE PRECISION := 0;
  i INTEGER;
BEGIN
  IF p_geojson IS NULL
     OR coalesce(p_geojson->>'type', '') <> 'LineString'
     OR jsonb_typeof(p_geojson->'coordinates') <> 'array' THEN
    RETURN NULL;
  END IF;

  -- Third coordinate of every point, NULL where absent or not a number.
  SELECT array_agg(
           CASE WHEN jsonb_typeof(c->2) = 'number' AND abs((c->>2)::numeric) < 100000
                THEN (c->>2)::double precision END
           ORDER BY ord)
    INTO v_raw
  FROM jsonb_array_elements(p_geojson->'coordinates') WITH ORDINALITY AS t(c, ord);

  v_n := coalesce(array_length(v_raw, 1), 0);
  IF v_n < 2 THEN RETURN NULL; END IF;

  SELECT count(*) INTO v_with_z FROM unnest(v_raw) AS u(z) WHERE z IS NOT NULL;
  IF v_with_z < 2 OR v_with_z < ceil(v_n * 0.9) THEN RETURN NULL; END IF;

  -- Drop the gaps (neighbours join across them, as gpxpy does).
  SELECT array_agg(z ORDER BY ord) INTO v_z
  FROM unnest(v_raw) WITH ORDINALITY AS u(z, ord)
  WHERE z IS NOT NULL;
  v_n := array_length(v_z, 1);

  -- 3-point weighted smoothing; the ends keep their raw value.
  v_smooth := v_z;
  FOR i IN 2..(v_n - 1) LOOP
    v_smooth[i] := 0.3 * v_z[i - 1] + 0.4 * v_z[i] + 0.3 * v_z[i + 1];
  END LOOP;

  -- Hysteresis: the reference only moves on a ≥ 5 m excursion.
  v_ref := v_smooth[1];
  FOR i IN 2..v_n LOOP
    IF v_smooth[i] - v_ref >= c_threshold THEN
      v_gain := v_gain + (v_smooth[i] - v_ref);
      v_ref := v_smooth[i];
    ELSIF v_ref - v_smooth[i] >= c_threshold THEN
      v_ref := v_smooth[i];
    END IF;
  END LOOP;

  RETURN round(v_gain)::integer;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_activity(p_sport_id uuid, p_title text, p_description text, p_level text, p_max_participants integer, p_meeting_lng double precision, p_meeting_lat double precision, p_end_lng double precision DEFAULT NULL::double precision, p_end_lat double precision DEFAULT NULL::double precision, p_starts_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_duration text DEFAULT '2 hours'::text, p_visibility text DEFAULT 'public'::text, p_requires_presence boolean DEFAULT true, p_objective_lng double precision DEFAULT NULL::double precision, p_objective_lat double precision DEFAULT NULL::double precision, p_objective_name text DEFAULT NULL::text, p_distance_km numeric DEFAULT NULL::numeric, p_elevation_gain_m integer DEFAULT NULL::integer, p_meeting_name text DEFAULT NULL::text, p_trace_geojson jsonb DEFAULT NULL::jsonb, p_level_max text DEFAULT NULL::text, p_meeting_locality text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_tier TEXT;
  v_is_admin BOOLEAN;
  v_daily_count INTEGER;
  v_monthly_count INTEGER;
  v_activity_id UUID;
  v_title TEXT;
  v_level_max TEXT;
  v_distance_km NUMERIC;
  v_elevation_gain_m INTEGER;
BEGIN
  -- Sensitive: generic.
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- User-actionable: coded.
  v_title := trim(p_title);
  IF char_length(v_title) < 3 THEN RAISE EXCEPTION 'junto.title_too_short'; END IF;

  -- Normalise the range high end: empty → NULL; equal to the low end → NULL
  -- (single level). Scale membership/ordering enforced client-side.
  v_level_max := NULLIF(trim(coalesce(p_level_max, '')), '');
  IF v_level_max = trim(p_level) THEN v_level_max := NULL; END IF;

  IF p_starts_at IS NULL OR p_starts_at <= NOW() THEN
    RAISE EXCEPTION 'junto.date_in_past';
  END IF;

  IF p_starts_at > NOW() + INTERVAL '6 months' THEN
    RAISE EXCEPTION 'junto.date_too_far';
  END IF;

  IF p_max_participants IS NOT NULL AND (p_max_participants < 2 OR p_max_participants > 50) THEN
    RAISE EXCEPTION 'junto.participants_range';
  END IF;

  -- Tamper guard (UI only sends valid values): generic.
  IF p_visibility NOT IN ('public', 'approval', 'private_link', 'private_link_approval') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00470 (audit M6): the trace is validated before anything else touches it.
  IF p_trace_geojson IS NOT NULL AND NOT trace_geojson_ok(p_trace_geojson) THEN
    RAISE EXCEPTION 'junto.trace_geojson_invalid';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_create_activity'));

  SELECT tier, coalesce(is_admin, FALSE) INTO v_tier, v_is_admin
  FROM users WHERE id = v_user_id;

  -- Private-link visibilities are open to everyone (Scott 2026-07-10):
  -- all tiers are free at launch. Premium gate removed.

  IF NOT v_is_admin THEN
    SELECT count(*) INTO v_daily_count
    FROM activities
    WHERE creator_id = v_user_id AND created_at > NOW() - INTERVAL '1 day';

    IF v_daily_count >= 10 THEN RAISE EXCEPTION 'junto.limit_daily'; END IF;

    SELECT count(*) INTO v_monthly_count
    FROM activities
    WHERE creator_id = v_user_id AND created_at > NOW() - INTERVAL '30 days';

    IF v_monthly_count >= 30 THEN RAISE EXCEPTION 'junto.limit_monthly'; END IF;
  END IF;

  -- Trace-derived prefill (00452), after the rate limits (00470, audit L7):
  -- the typed value always wins; a derived figure outside the column's range
  -- (flat or descending trace → 0 m, degenerate or absurd distance) stays
  -- NULL instead of failing the insert (00470, audit M5).
  v_distance_km := p_distance_km;
  v_elevation_gain_m := p_elevation_gain_m;
  IF p_trace_geojson IS NOT NULL THEN
    IF v_distance_km IS NULL THEN
      v_distance_km := trace_distance_km(p_trace_geojson);
      IF v_distance_km <= 0 OR v_distance_km > 9999 THEN v_distance_km := NULL; END IF;
    END IF;
    IF v_elevation_gain_m IS NULL THEN
      v_elevation_gain_m := NULLIF(trace_elevation_gain_m(p_trace_geojson), 0);
      IF v_elevation_gain_m > 99999 THEN v_elevation_gain_m := NULL; END IF;
    END IF;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  INSERT INTO activities (
    creator_id, sport_id, title, description, level, level_max,
    max_participants, location_meeting, location_end,
    location_objective, objective_name, meeting_name, meeting_locality,
    distance_km, elevation_gain_m,
    starts_at, duration, visibility, requires_presence,
    trace_geojson,
    status, created_at, updated_at
  ) VALUES (
    v_user_id, p_sport_id, v_title, trim(p_description), p_level, v_level_max,
    p_max_participants,
    ST_SetSRID(ST_MakePoint(p_meeting_lng, p_meeting_lat), 4326)::geography,
    CASE WHEN p_end_lng IS NOT NULL AND p_end_lat IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_end_lng, p_end_lat), 4326)::geography
      ELSE NULL END,
    CASE WHEN p_objective_lng IS NOT NULL AND p_objective_lat IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_objective_lng, p_objective_lat), 4326)::geography
      ELSE NULL END,
    CASE WHEN p_objective_name IS NOT NULL AND char_length(trim(p_objective_name)) > 0
      THEN trim(p_objective_name) ELSE NULL END,
    CASE WHEN p_meeting_name IS NOT NULL AND char_length(trim(p_meeting_name)) > 0
      THEN trim(p_meeting_name) ELSE NULL END,
    CASE WHEN p_meeting_locality IS NOT NULL AND char_length(trim(p_meeting_locality)) > 0
      THEN left(trim(p_meeting_locality), 80) ELSE NULL END,
    v_distance_km,
    v_elevation_gain_m,
    p_starts_at, p_duration::interval, p_visibility, coalesce(p_requires_presence, TRUE),
    p_trace_geojson,
    'published', now(), now()
  ) RETURNING id INTO v_activity_id;

  INSERT INTO participations (activity_id, user_id, status, created_at)
  VALUES (v_activity_id, v_user_id, 'accepted', now());

  IF p_visibility IN ('public', 'approval') THEN
    PERFORM check_alerts_for_activity(v_activity_id);
  END IF;

  RETURN v_activity_id;
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
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

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

  PERFORM set_config('junto.bypass_lock', 'true', true);

  UPDATE activities
  SET trace_geojson = p_trace_geojson,
      distance_km = CASE
        WHEN p_trace_geojson IS NOT NULL AND distance_km IS NULL
          THEN (SELECT CASE WHEN d > 0 AND d <= 9999 THEN d END FROM (SELECT trace_distance_km(p_trace_geojson) AS d) x)
        ELSE distance_km END,
      elevation_gain_m = CASE
        WHEN p_trace_geojson IS NOT NULL AND elevation_gain_m IS NULL
          THEN (SELECT CASE WHEN g > 0 AND g <= 99999 THEN g END FROM (SELECT trace_elevation_gain_m(p_trace_geojson) AS g) x)
        ELSE elevation_gain_m END,
      updated_at = now()
  WHERE id = p_activity_id;
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
