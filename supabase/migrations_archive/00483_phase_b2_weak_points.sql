-- ============================================================================
-- 00483 — Phase B2 (fin) : les deux points faibles laissés ouverts.
--
-- 1. Signal carte quand l'organisateur change de nom ou d'avatar (affichés
--    sur la carte) ou quand il est suspendu / réactivé (ses sorties
--    disparaissent / réapparaissent) : un signal par sortie visible concernée,
--    limité comme les autres (≤ 1 par sortie toutes les 15 s).
-- 2. Trace invalide envoyée à update_activity_trace : la tentative est
--    désormais COMPTÉE (la fonction renvoie le code au lieu de lever une
--    exception, qui annulait le compteur). L'app lève l'erreur côté client.
--    En plus, trace_geojson_ok est réécrite en jsonpath (31 ms → 2 ms sur
--    10 000 points) : un appel raté coûte désormais autant qu'une requête
--    ordinaire, pour les cinq fonctions qui valident une trace.
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
    -- Same per-point rules as before (00470), evaluated in C by jsonpath.
    -- strict mode: no automatic unwrapping of the coordinate arrays.
    AND NOT jsonb_path_exists(p_geojson, 'strict $.coordinates[*] ? (
         @.type() != "array"
      || @.size() < 2 || @.size() > 4
      || @[0].type() != "number" || @[1].type() != "number"
      || @[0] < -180 || @[0] > 180 || @[1] < -90 || @[1] > 90
      || (@.size() >= 3 && @[2].type() != "number" && @[2].type() != "null")
      || (@.size() >= 3 && @[2].type() == "number" && (@[2] < -100000 || @[2] > 100000))
      || (@.size() == 4 && @[3].type() != "number" && @[3].type() != "null")
      || (@.size() == 4 && @[3].type() == "number" && (@[3] < -1e13 || @[3] > 1e13))
    )');
$function$;

DROP FUNCTION public.update_activity_trace(uuid, jsonb);
CREATE OR REPLACE FUNCTION public.update_activity_trace(p_activity_id uuid, p_trace_geojson jsonb)
 RETURNS text
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
  -- 00483: an invalid trace is REPORTED, not raised, so the frequency
  -- counter above stays committed (a raise rolled it back and made the
  -- failing path free). NULL = saved; a junto.<code> = refused.
  IF p_trace_geojson IS NOT NULL AND NOT trace_geojson_ok(p_trace_geojson) THEN
    RETURN 'junto.trace_geojson_invalid';
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
  RETURN NULL;
END;
$function$;
REVOKE ALL ON FUNCTION public.update_activity_trace(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_activity_trace(uuid, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.broadcast_map_creator()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_activity UUID;
BEGIN
  FOR v_activity IN
    SELECT id FROM activities
    WHERE creator_id = NEW.id
      AND visibility IN ('public', 'approval')
      AND NOT is_demo
      AND status IN ('published', 'in_progress')
      AND deleted_at IS NULL
  LOOP
    PERFORM map_ping(v_activity);
  END LOOP;
  RETURN NULL;
END;
$function$;
REVOKE ALL ON FUNCTION public.broadcast_map_creator() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_users_map_broadcast ON users;
CREATE TRIGGER trg_users_map_broadcast
  AFTER UPDATE OF display_name, avatar_url, suspended_at ON users
  FOR EACH ROW
  WHEN (NEW.display_name IS DISTINCT FROM OLD.display_name
        OR NEW.avatar_url IS DISTINCT FROM OLD.avatar_url
        OR (NEW.suspended_at IS NULL) IS DISTINCT FROM (OLD.suspended_at IS NULL))
  EXECUTE FUNCTION broadcast_map_creator();
