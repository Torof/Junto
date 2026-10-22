-- ============================================================================
-- 00488 — Contre-vérification du lot vie privée 1.
-- DX-1  Une absence se déduisait encore : une sortie finalisée n'a que des
--       « présent » / « absent », donc « rien » = absent. Les non-membres ne
--       reçoivent plus aucune coche ; la revue entre pairs ne renvoie plus
--       « absent » ; le score brut de get_user_public_stats n'est plus public.
-- AC-2  get_transport_summary exposait les noms de départ (texte libre,
--       souvent une adresse) à tout compte : membres seulement, sans blocage ;
--       participants retirés exclus d'une sortie privée.
--       get_activity_seat_assignments : point de prise en charge réservé au
--       conducteur, au passager et à l'organisateur une fois la sortie
--       terminée ; blocage pris dans les deux sens.
-- upsert_dispo : le compteur ne compte qu'une fois toutes les vérifications passées.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_activity_participants(p_activity_id uuid)
 RETURNS TABLE(participation_id uuid, activity_id uuid, user_id uuid, status text, created_at timestamp with time zone, left_at timestamp with time zone, confirmed_present boolean, transport_type text, transport_seats smallint, transport_from_name text, transport_departs_at timestamp with time zone, transport_from_lat double precision, transport_from_lng double precision, display_name text, avatar_url text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_is_creator BOOLEAN;
  v_is_member BOOLEAN;
  v_live BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities a
    WHERE a.id = p_activity_id
      -- 00472 (audit L3): the demo curtain, like every other read surface.
      AND (a.is_demo = false OR demo_content_visible())
      AND (
        a.visibility IN ('public', 'approval')
        OR a.creator_id = v_user_id
        -- 00485 (AC-2): only an ACCEPTED participant, not a removed / left one.
        OR EXISTS (
          SELECT 1 FROM participations p
          WHERE p.activity_id = a.id AND p.user_id = v_user_id AND p.status = 'accepted'
        )
      )
  ) THEN
    RETURN;
  END IF;

  SELECT a.creator_id = v_user_id, a.status IN ('published', 'in_progress')
    INTO v_is_creator, v_live
  FROM activities a WHERE a.id = p_activity_id;
  v_is_member := v_is_creator OR EXISTS (
    SELECT 1 FROM participations p
    WHERE p.activity_id = p_activity_id AND p.user_id = v_user_id AND p.status = 'accepted');

  RETURN QUERY
  SELECT
    p.id AS participation_id,
    p.activity_id,
    p.user_id,
    p.status,
    p.created_at,
    p.left_at,
    -- 00485 (DX-1): an absence is shown only to the organiser and to the
    -- person concerned; everyone else sees « present » or nothing.
    CASE WHEN p.user_id = v_user_id OR v_is_creator THEN p.confirmed_present
         -- 00488: only fellow members see « present » (once an outing is
         -- finalised, a missing tick would otherwise read as an absence).
         WHEN v_is_member AND p.confirmed_present THEN true ELSE NULL END,
    p.transport_type,
    p.transport_seats,
    -- 00485 (AC-2): a driver's starting point (often home) is shown only to
    -- the outing's accepted members, while it is upcoming / under way, and
    -- never across a block.
    CASE WHEN (p.user_id = v_user_id OR (v_is_member AND v_live AND NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE (b.blocker_id = v_user_id AND b.blocked_id = p.user_id)
         OR (b.blocker_id = p.user_id AND b.blocked_id = v_user_id)))) THEN p.transport_from_name END,
    p.transport_departs_at,
    CASE WHEN (p.user_id = v_user_id OR (v_is_member AND v_live AND NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE (b.blocker_id = v_user_id AND b.blocked_id = p.user_id)
         OR (b.blocker_id = p.user_id AND b.blocked_id = v_user_id)))) THEN p.transport_from_lat END,
    CASE WHEN (p.user_id = v_user_id OR (v_is_member AND v_live AND NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE (b.blocker_id = v_user_id AND b.blocked_id = p.user_id)
         OR (b.blocker_id = p.user_id AND b.blocked_id = v_user_id)))) THEN p.transport_from_lng END,
    pp.display_name,
    pp.avatar_url
  FROM participations p
  JOIN public_profiles pp ON pp.id = p.user_id
  WHERE p.activity_id = p_activity_id
    AND p.status = 'accepted'
    AND p.user_id NOT IN (
      SELECT blocked_id FROM blocked_users WHERE blocker_id = v_user_id
    )
  ORDER BY p.created_at;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_activity_peer_review_state(p_activity_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_result jsonb;
  v_sport_key TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT s.key INTO v_sport_key
  FROM activities a
  JOIN sports s ON s.id = a.sport_id
  WHERE a.id = p_activity_id;

  SELECT jsonb_agg(
    jsonb_build_object(
      'user_id',                p.user_id,
      'display_name',           pp.display_name,
      'avatar_url',             pp.avatar_url,
      -- 00488 (DX-1): never echo an absence to co-participants.
      'confirmed_present',      CASE WHEN p.confirmed_present THEN true END,
      'peer_validation_count',  coalesce(pv_counts.cnt, 0),
      'i_voted_presence',       EXISTS (
        SELECT 1 FROM peer_validations
        WHERE voter_id = v_user_id
          AND voted_id = p.user_id
          AND activity_id = p_activity_id
      ),
      'my_badge_votes',         coalesce(my_votes.keys, ARRAY[]::TEXT[]),
      'declared_level',         NULLIF(pp.levels_per_sport ->> v_sport_key, '')
    )
  ) INTO v_result
  FROM participations p
  JOIN public_profiles pp ON pp.id = p.user_id
  LEFT JOIN (
    SELECT voted_id, count(*)::int AS cnt
    FROM peer_validations
    WHERE activity_id = p_activity_id
    GROUP BY voted_id
  ) pv_counts ON pv_counts.voted_id = p.user_id
  LEFT JOIN (
    SELECT voted_id, array_agg(badge_key) AS keys
    FROM reputation_votes
    WHERE activity_id = p_activity_id AND voter_id = v_user_id
    GROUP BY voted_id
  ) my_votes ON my_votes.voted_id = p.user_id
  WHERE p.activity_id = p_activity_id
    AND p.status = 'accepted'
    AND p.user_id != v_user_id;

  RETURN coalesce(v_result, '[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_user_public_stats(p_user_id uuid)
 RETURNS TABLE(total_activities integer, completed_activities integer, created_activities integer, joined_activities integer, sports_count integer, reliability_score double precision, reliability_tier text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- 00419 M3 : rideau démo.
  IF EXISTS (SELECT 1 FROM users du WHERE du.id = p_user_id AND du.is_demo = true)
     AND NOT demo_content_visible() THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH real_outings AS (
    SELECT a.id, a.creator_id
    FROM participations par
    JOIN activities a ON a.id = par.activity_id
    WHERE par.user_id = p_user_id
      AND par.status = 'accepted'
      AND par.confirmed_present IS DISTINCT FROM false
      AND a.status = 'completed'
      AND a.deleted_at IS NULL
  )
  SELECT
    (SELECT count(*)::int FROM real_outings) AS total_activities,
    (SELECT count(*)::int FROM real_outings) AS completed_activities,
    (SELECT count(*)::int FROM real_outings WHERE creator_id = p_user_id) AS created_activities,
    (SELECT count(*)::int FROM real_outings WHERE creator_id != p_user_id) AS joined_activities,
    (SELECT count(DISTINCT jsonb_array_elements_text)::int
     FROM users, jsonb_array_elements_text(sports)
     WHERE users.id = p_user_id) AS sports_count,
    -- 00488: the raw score is not public (public_profiles hides it since
    -- 00347); only the tier below is.
    NULL::double precision AS reliability_score,
    (SELECT public.reliability_tier(u.reliability_score)
     FROM users u WHERE u.id = p_user_id) AS reliability_tier;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_transport_summary(p_activity_id uuid)
 RETURNS TABLE(transport_type text, count integer, total_seats integer, cities text[])
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_is_member BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities a
    WHERE a.id = p_activity_id
      AND a.status IN ('published', 'in_progress')
      AND a.deleted_at IS NULL
      AND (a.is_demo = false OR demo_content_visible())
      AND (
        a.visibility IN ('public', 'approval')
        OR a.creator_id = v_user_id
        OR EXISTS (
          SELECT 1 FROM participations p
          WHERE p.activity_id = a.id AND p.user_id = v_user_id AND p.status = 'accepted'
        )
      )
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_is_member := EXISTS (SELECT 1 FROM activities a WHERE a.id = p_activity_id AND a.creator_id = v_user_id)
    OR EXISTS (SELECT 1 FROM participations p WHERE p.activity_id = p_activity_id AND p.user_id = v_user_id AND p.status = 'accepted');

  RETURN QUERY
  SELECT
    p.transport_type,
    count(*)::int AS count,
    COALESCE(sum(p.transport_seats)::int, 0) AS total_seats,
    -- 00488 (AC-2): departure place names are free text (often an address):
    -- shown to the outing's members only, never across a block.
    array_agg(DISTINCT p.transport_from_name) FILTER (
      WHERE p.transport_from_name IS NOT NULL AND v_is_member
        AND NOT EXISTS (SELECT 1 FROM blocked_users b
          WHERE (b.blocker_id = v_user_id AND b.blocked_id = p.user_id)
             OR (b.blocker_id = p.user_id AND b.blocked_id = v_user_id))) AS cities
  FROM participations p
  WHERE p.activity_id = p_activity_id
    AND p.status = 'accepted'
    AND p.transport_type IS NOT NULL
  GROUP BY p.transport_type
  ORDER BY count DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_activity_seat_assignments(p_activity_id uuid)
 RETURNS TABLE(id uuid, driver_id uuid, requester_id uuid, display_name text, avatar_url text, pickup_from text, requested_pickup_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_creator UUID;
  v_live BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.user_id = v_user_id
      AND p.status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT a.creator_id, a.status IN ('published', 'in_progress') INTO v_creator, v_live
  FROM activities a WHERE a.id = p_activity_id;

  RETURN QUERY
    SELECT
      sr.id,
      sr.driver_id,
      sr.requester_id,
      pp.display_name,
      pp.avatar_url,
      -- 00488: a pickup point (often home) goes to the driver, the passenger
      -- and the organiser; other members see it only while the outing is live.
      CASE WHEN v_user_id IN (sr.driver_id, sr.requester_id, v_creator) OR v_live THEN sr.pickup_from END,
      CASE WHEN v_user_id IN (sr.driver_id, sr.requester_id, v_creator) OR v_live THEN sr.requested_pickup_at END
    FROM seat_requests sr
    JOIN public_profiles pp ON pp.id = sr.requester_id
    WHERE sr.activity_id = p_activity_id
      AND sr.status = 'accepted'
      AND NOT EXISTS (
        SELECT 1 FROM blocked_users b
        WHERE (b.blocker_id = v_user_id AND b.blocked_id IN (sr.driver_id, sr.requester_id))
           OR (b.blocked_id = v_user_id AND b.blocker_id IN (sr.driver_id, sr.requester_id))
      );
END;
$function$;

CREATE OR REPLACE FUNCTION public.upsert_dispo(p_sport_keys text[], p_levels jsonb, p_base_lng double precision, p_base_lat double precision, p_base_label text, p_radius_km integer, p_transport_modes text[], p_window_start timestamp with time zone, p_window_end timestamp with time zone, p_intent text[] DEFAULT NULL::text[], p_about text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_id UUID;
  v_label TEXT;
  v_intent TEXT[];
  v_about TEXT;
  v_lng DOUBLE PRECISION;
  v_lat DOUBLE PRECISION;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_sport_keys IS NULL OR array_length(p_sport_keys, 1) IS NULL
     OR array_length(p_sport_keys, 1) NOT BETWEEN 1 AND 3
     OR EXISTS (SELECT 1 FROM unnest(p_sport_keys) k
                WHERE NOT EXISTS (SELECT 1 FROM sports s WHERE s.key = k AND s.is_active))
  THEN RAISE EXCEPTION 'junto.dispo_sports'; END IF;

  -- Levels: optional. If present it MUST be an object whose keys ⊆ chosen sports
  -- and whose values are short strings (cotation codes) — no unbounded / non-object
  -- blob can be stored and fanned out to matches.
  IF p_levels IS NOT NULL THEN
    IF jsonb_typeof(p_levels) <> 'object'
       OR EXISTS (
         SELECT 1 FROM jsonb_object_keys(p_levels) AS lk(sport)
         WHERE lk.sport <> ALL(p_sport_keys)
       )
       OR EXISTS (
         SELECT 1 FROM jsonb_each_text(p_levels) AS e(k, v)
         WHERE v IS NULL OR char_length(v) > 20
       )
    THEN RAISE EXCEPTION 'junto.dispo_levels'; END IF;
  END IF;

  IF p_intent IS NULL OR cardinality(p_intent) = 0 THEN
    v_intent := NULL;
  ELSIF NOT (p_intent <@ ARRAY[
              'discovery','progression','performance','detente','conviviality',
              'dog','child','group','solo','active','calm','early',
              'nature','challenge','photo','mixed','same_level','beginners',
              'long_outing','after_work','regular','adapted','training',
              'experienced','competition'
            ]::text[])
        OR cardinality(p_intent) > 10 THEN
    RAISE EXCEPTION 'junto.dispo_intent';
  ELSE
    v_intent := p_intent;
  END IF;

  v_about := NULLIF(trim(regexp_replace(COALESCE(p_about, ''), '<[^>]*>', '', 'g')), '');
  IF v_about IS NOT NULL AND (
       char_length(v_about) > 1600
       OR array_length(regexp_split_to_array(v_about, '\s+'), 1) > 250
     ) THEN
    RAISE EXCEPTION 'junto.dispo_about';
  END IF;

  IF p_radius_km IS NOT NULL AND p_radius_km NOT IN (5, 10, 15, 30, 50) THEN
    RAISE EXCEPTION 'junto.dispo_radius';
  END IF;

  IF p_transport_modes IS NULL OR array_length(p_transport_modes, 1) IS NULL
     OR array_length(p_transport_modes, 1) < 1
     OR NOT (p_transport_modes <@ ARRAY['car', 'motorbike', 'bike', 'on_foot', 'public_transport'])
  THEN RAISE EXCEPTION 'junto.dispo_transport'; END IF;

  IF p_window_start IS NULL OR p_window_end IS NULL OR p_window_end <= p_window_start
     OR p_window_end > now() + INTERVAL '4 weeks' OR p_window_start < now() - INTERVAL '1 day'
  THEN RAISE EXCEPTION 'junto.dispo_window'; END IF;

  IF p_base_lng IS NULL OR p_base_lat IS NULL
     OR p_base_lng NOT BETWEEN -180 AND 180 OR p_base_lat NOT BETWEEN -90 AND 90
  THEN RAISE EXCEPTION 'junto.dispo_place'; END IF;

  -- 00485 (DC-1 / DX-2): the base is rounded to ~1 km BEFORE it is stored,
  -- so no read or matching probe can ever recover an exact address.
  v_lng := round(p_base_lng::numeric, 2)::float8;
  v_lat := round(p_base_lat::numeric, 2)::float8;

  v_label := NULLIF(trim(regexp_replace(COALESCE(p_base_label, ''), '<[^>]*>', '', 'g')), '');
  IF v_label IS NULL OR char_length(v_label) > 120 THEN
    RAISE EXCEPTION 'junto.dispo_place';
  END IF;

  -- 00488: counted only once every input check has passed.
  PERFORM private.rate_hit('dispo', 30, INTERVAL '1 day');

  SELECT id INTO v_id FROM discovery_availabilities WHERE user_id = v_user_id LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO discovery_availabilities
      (user_id, sport_keys, levels, intent, about, base, base_label, radius_km, transport_modes, window_start, window_end)
    VALUES
      (v_user_id, p_sport_keys, p_levels, v_intent, v_about,
       ST_SetSRID(ST_MakePoint(v_lng, v_lat), 4326)::geography,
       v_label, p_radius_km, p_transport_modes, p_window_start, p_window_end)
    RETURNING id INTO v_id;
  ELSE
    UPDATE discovery_availabilities SET
      sport_keys = p_sport_keys, levels = p_levels, intent = v_intent, about = v_about,
      base = ST_SetSRID(ST_MakePoint(v_lng, v_lat), 4326)::geography,
      base_label = v_label, radius_km = p_radius_km, transport_modes = p_transport_modes,
      window_start = p_window_start, window_end = p_window_end
    WHERE id = v_id;
  END IF;
  RETURN v_id;
END;
$function$;
