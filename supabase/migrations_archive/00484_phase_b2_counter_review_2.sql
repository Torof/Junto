-- ============================================================================
-- 00484 — Contre-vérification de 00483.
-- * trace_geojson_ok : un objet sans clé `coordinates` faisait lever une
--   erreur brute (mode strict) et un objet sans `type` rendait NULL, que les
--   appelants laissaient passer. Désormais : clés exigées, mode silencieux,
--   résultat jamais NULL. Les nombres infinitésimaux (1e-400), qui faisaient
--   planter le calcul de D+ après le compteur, sont refusés.
-- * Signal carte organisateur : UN signal par changement de profil (le signal
--   est sans contenu, un par sortie était redondant), au plus un toutes les
--   15 s par organisateur et 30 par heure.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.trace_geojson_ok(p_geojson jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  -- 00484: coalesce — a missing key made the whole test NULL, and callers
  -- write `IF NOT trace_geojson_ok(x)`, so NULL let the trace through.
  SELECT coalesce(p_geojson IS NOT NULL
    AND pg_column_size(p_geojson) <= 1000000
    AND jsonb_typeof(p_geojson) = 'object'
    AND p_geojson ? 'type' AND p_geojson ? 'coordinates'
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
      || (@[0] != 0 && @[0] > -1e-300 && @[0] < 1e-300)
      || (@[1] != 0 && @[1] > -1e-300 && @[1] < 1e-300)
      || (@.size() >= 3 && @[2].type() == "number" && @[2] != 0 && @[2] > -1e-300 && @[2] < 1e-300)
      || (@.size() == 4 && @[3].type() == "number" && @[3] != 0 && @[3] > -1e-300 && @[3] < 1e-300)
    )', '{}', true), false);
$function$;

CREATE OR REPLACE FUNCTION public.broadcast_map_creator()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE creator_id = NEW.id
      AND visibility IN ('public', 'approval')
      AND NOT is_demo
      AND status IN ('published', 'in_progress')
      AND deleted_at IS NULL
  ) THEN RETURN NULL; END IF;
  -- Hourly budget without raising (a profile save must never fail for a ping).
  PERFORM pg_advisory_xact_lock(hashtext(NEW.id::text || '_rate_creator_map'));
  IF (SELECT count(*) FROM rate_events
      WHERE user_id = NEW.id AND kind = 'creator_map' AND at > now() - INTERVAL '1 hour') >= 30 THEN
    RETURN NULL;
  END IF;
  INSERT INTO rate_events (user_id, kind) VALUES (NEW.id, 'creator_map');
  -- The creator id is the throttle key (map_broadcasts has no FK): one
  -- content-less ping per creator change, ≤ 1 per 15 s.
  PERFORM map_ping(NEW.id);
  RETURN NULL;
END;
$function$;
REVOKE ALL ON FUNCTION public.broadcast_map_creator() FROM PUBLIC, anon, authenticated;
