-- ============================================================================
-- 00482 — Phase B2 (contre-vérification) :
-- * compute_trace_stats : une trace invalide est désormais COMPTÉE (avant,
--   l'exception annulait le compteur : le chemin coûteux qui échoue était
--   gratuit) ; plafond relevé à 600 / h (le tracé appelle le calcul à chaque
--   point ajouté, 120 / h était atteignable en usage normal).
-- * share_trace_message : taille et fréquence vérifiées AVANT le parcours des
--   coordonnées ; budget de 5 Mo compté en octets bruts des deux côtés.
-- * Matériel : plafond horaire en plus du plafond à la minute.
-- * Droits résiduels : plus d'INSERT/UPDATE/DELETE/TRUNCATE client sur
--   activities, activity_gear, activity_gear_missing (tout passe par les RPC).
-- ============================================================================

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
  PERFORM private.rate_hit('trace_stats', 600, INTERVAL '1 hour');

  -- 00482: everything after the counter runs in a sub-block that swallows
  -- its own failures, so an invalid trace still COUNTS (a raise would roll
  -- the counter back and make the expensive failing path free). An invalid
  -- trace now yields no stats, which the client already treats as "none".
  BEGIN
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
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT NULL::numeric, NULL::integer;
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
  -- 00482: size and frequency gates BEFORE the per-coordinate scan, so a
  -- caller over the limits cannot make the database do the expensive work.
  IF octet_length(p_trace_geojson::text) > 1000000 THEN RAISE EXCEPTION 'junto.trace_too_large'; END IF;
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
  -- 00480: byte budget too (20 × 1 MB a day per account was still a lot).
  -- 00482: raw bytes on both sides (pg_column_size of a stored row is the
  -- compressed size, which undercounted earlier shares).
  IF (SELECT coalesce(sum(octet_length((metadata->'trace_geojson')::text)), 0) FROM messages
      WHERE sender_id = v_user_id AND metadata->>'type' = 'shared_trace'
        AND created_at > now() - INTERVAL '24 hours') + octet_length(p_trace_geojson::text) > 5000000 THEN
    RAISE EXCEPTION 'junto.share_daily_cap';
  END IF;

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

  IF NOT trace_geojson_ok(p_trace_geojson) THEN RAISE EXCEPTION 'junto.trace_geojson_invalid'; END IF;

  v_clean_name := CASE
    WHEN p_name IS NOT NULL AND char_length(trim(p_name)) > 0
    THEN substring(regexp_replace(trim(p_name), '<[^>]*>', '', 'g') from 1 for 100)
    ELSE 'trace.gpx'
  END;

  RETURN private.insert_rich_message(
    p_conversation_id, v_user_id,
    '🗺️ ' || v_clean_name,
    jsonb_build_object('type', 'shared_trace', 'name', v_clean_name, 'trace_geojson', p_trace_geojson)
  );
END;
$function$;

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
  PERFORM private.rate_hit('gear_h', 200, INTERVAL '1 hour');

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

  -- 00481: the per-item loop below is one INSERT statement per item, so the
  -- statement-level ping fired once per item. Silence it for the rewrite and
  -- send a single ping at the end.
  PERFORM set_config('junto.gear_quiet', 'true', true);
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
  PERFORM set_config('junto.gear_quiet', 'false', true);
  BEGIN
    PERFORM realtime.send(jsonb_build_object('table', 'activity_gear', 'op', 'UPDATE'), 'change', 'activity:' || p_activity_id::text, true);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
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
  PERFORM private.rate_hit('gear_missing_h', 300, INTERVAL '1 hour');

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
  PERFORM private.rate_hit('gear_missing_h', 300, INTERVAL '1 hour');

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

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON activities FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON activity_gear FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON activity_gear_missing FROM anon, authenticated;
