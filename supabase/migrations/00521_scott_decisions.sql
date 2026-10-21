-- ============================================================================
-- 00521 — Décisions Scott (2026-10-22) après le dernier audit.
-- 1. Deux personnes qui se bloquent ne se retrouvent pas dans la même sortie
--    (rejoindre, demander, accepter, invitation : déclencheur unique).
-- 2/4. Point de départ des conducteurs : le point exact seulement pour ses
--    passagers ; les autres membres et le résumé covoiturage voient le village
--    (transport_from_locality, géocodé par l'app comme le lieu-dit du
--    rendez-vous). Point de prise en charge : conducteur, passager, organisateur.
-- 3. Niveaux, trophées, badges, nombre de sorties : seules les présences
--    VALIDÉES comptent (une sortie sans validation ne fabrique plus de niveau).
-- 5. Plafond de fichiers par compte et par espace de stockage.
-- 6. L'admin est prévenu quand une vitrine pro approuvée change de nom.
-- ============================================================================

ALTER TABLE participations ADD COLUMN IF NOT EXISTS transport_from_locality TEXT
  CHECK (transport_from_locality IS NULL OR char_length(transport_from_locality) <= 80);

DROP FUNCTION public.set_participation_transport(uuid, text, smallint, text, timestamp with time zone, double precision, double precision);
CREATE OR REPLACE FUNCTION public.set_participation_transport(p_activity_id uuid, p_transport_type text, p_transport_seats smallint DEFAULT NULL::smallint, p_transport_from_name text DEFAULT NULL::text, p_transport_departs_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_transport_from_lat double precision DEFAULT NULL::double precision, p_transport_from_lng double precision DEFAULT NULL::double precision, p_transport_from_locality text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_starts_at TIMESTAMPTZ;
  v_from_name TEXT;
  v_lat DOUBLE PRECISION;
  v_lng DOUBLE PRECISION;
  v_locality TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  PERFORM private.rate_hit('transport', 20, INTERVAL '1 minute');  -- 00516 (L5)

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

  IF p_transport_type IS NOT NULL
     AND p_transport_type NOT IN ('car', 'public_transport', 'bike', 'on_foot', 'other') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00496 (BR-3): someone seated in another car does not offer seats.
  IF p_transport_type = 'car' AND coalesce(p_transport_seats, 0) > 0
     AND EXISTS (SELECT 1 FROM seat_requests
                 WHERE activity_id = p_activity_id AND requester_id = v_user_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'junto.already_seated';
  END IF;

  IF (p_transport_type IS NULL OR p_transport_type != 'car')
     AND EXISTS (
       SELECT 1 FROM seat_requests
       WHERE activity_id = p_activity_id
         AND driver_id = v_user_id
         AND status = 'accepted'
     ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_transport_type != 'car' AND p_transport_seats IS NOT NULL AND p_transport_seats > 0 THEN
    p_transport_seats := NULL;
  END IF;

  IF p_transport_departs_at IS NOT NULL THEN
    SELECT starts_at INTO v_starts_at FROM activities WHERE id = p_activity_id;
    IF p_transport_departs_at < v_starts_at - INTERVAL '12 hours'
       OR p_transport_departs_at > v_starts_at + INTERVAL '6 hours' THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  v_from_name := CASE
    WHEN p_transport_from_name IS NOT NULL AND char_length(trim(p_transport_from_name)) > 0
    THEN regexp_replace(trim(p_transport_from_name), '<[^>]*>', '', 'g')
    ELSE NULL
  END;

  -- Coords only meaningful with a name; range-validated; cleared with the name
  -- (a free-text departure has a name but no coords).
  IF v_from_name IS NULL THEN
    v_lat := NULL; v_lng := NULL;
  ELSE
    IF p_transport_from_lat IS NOT NULL AND p_transport_from_lat NOT BETWEEN -90 AND 90 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF p_transport_from_lng IS NOT NULL AND p_transport_from_lng NOT BETWEEN -180 AND 180 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    v_lat := p_transport_from_lat; v_lng := p_transport_from_lng;
  END IF;

  -- 00521: the village / commune of the start point (reverse-geocoded by the
  -- app, like meeting_locality) — the only start information shown to members
  -- who are not this driver's passengers, and in the carpool summary.
  v_locality := CASE WHEN v_from_name IS NULL THEN NULL ELSE
    NULLIF(left(trim(regexp_replace(regexp_replace(coalesce(p_transport_from_locality, ''), '<[^>]*>', '', 'g'), '[[:cntrl:]]', ' ', 'g')), 80), '') END;

  UPDATE participations
  SET transport_type = p_transport_type,
      transport_seats = p_transport_seats,
      transport_from_name = v_from_name,
      transport_departs_at = p_transport_departs_at,
      transport_from_lat = v_lat,
      transport_from_lng = v_lng,
      transport_from_locality = v_locality
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';
END;
$function$;
GRANT EXECUTE ON FUNCTION public.set_participation_transport(uuid, text, smallint, text, timestamp with time zone, double precision, double precision, text) TO authenticated;

DROP FUNCTION public.get_activity_participants(uuid);
CREATE OR REPLACE FUNCTION public.get_activity_participants(p_activity_id uuid)
 RETURNS TABLE(participation_id uuid, activity_id uuid, user_id uuid, status text, created_at timestamp with time zone, left_at timestamp with time zone, confirmed_present boolean, transport_type text, transport_seats smallint, transport_from_name text, transport_departs_at timestamp with time zone, transport_from_lat double precision, transport_from_lng double precision, display_name text, avatar_url text, transport_from_locality text)
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
      AND a.deleted_at IS NULL  -- 00516
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
    -- 00490: per-person transport for members only (places are public in
    -- the transport summary; who leaves from where is not).
    CASE WHEN p.user_id = v_user_id OR v_is_member THEN p.transport_type END,
    -- 00490: per-person transport for members only (places are public in
    -- the transport summary; who leaves from where is not).
    CASE WHEN p.user_id = v_user_id OR v_is_member THEN p.transport_seats END,
    -- 00485 (AC-2): a driver's starting point (often home) is shown only to
    -- the outing's accepted members, while it is upcoming / under way, and
    -- never across a block.
    -- 00521: the exact start point (often home) only for the driver's own
    -- accepted passengers; other members see the village (last column).
    CASE WHEN (p.user_id = v_user_id OR (v_live AND EXISTS (
      SELECT 1 FROM seat_requests sr WHERE sr.activity_id = p_activity_id
        AND sr.driver_id = p.user_id AND sr.requester_id = v_user_id AND sr.status = 'accepted')
      AND NOT EXISTS (SELECT 1 FROM blocked_users b
        WHERE (b.blocker_id = v_user_id AND b.blocked_id = p.user_id)
           OR (b.blocker_id = p.user_id AND b.blocked_id = v_user_id)))) THEN p.transport_from_name END,
    -- 00490: per-person transport for members only (places are public in
    -- the transport summary; who leaves from where is not).
    CASE WHEN p.user_id = v_user_id OR v_is_member THEN p.transport_departs_at END,
    CASE WHEN (p.user_id = v_user_id OR (v_live AND EXISTS (
      SELECT 1 FROM seat_requests sr WHERE sr.activity_id = p_activity_id
        AND sr.driver_id = p.user_id AND sr.requester_id = v_user_id AND sr.status = 'accepted')
      AND NOT EXISTS (SELECT 1 FROM blocked_users b
        WHERE (b.blocker_id = v_user_id AND b.blocked_id = p.user_id)
           OR (b.blocker_id = p.user_id AND b.blocked_id = v_user_id)))) THEN p.transport_from_lat END,
    CASE WHEN (p.user_id = v_user_id OR (v_live AND EXISTS (
      SELECT 1 FROM seat_requests sr WHERE sr.activity_id = p_activity_id
        AND sr.driver_id = p.user_id AND sr.requester_id = v_user_id AND sr.status = 'accepted')
      AND NOT EXISTS (SELECT 1 FROM blocked_users b
        WHERE (b.blocker_id = v_user_id AND b.blocked_id = p.user_id)
           OR (b.blocker_id = p.user_id AND b.blocked_id = v_user_id)))) THEN p.transport_from_lng END,
    pp.display_name,
    pp.avatar_url,
    CASE WHEN (p.user_id = v_user_id OR (v_is_member AND v_live AND NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE (b.blocker_id = v_user_id AND b.blocked_id = p.user_id)
         OR (b.blocker_id = p.user_id AND b.blocked_id = v_user_id)))) THEN p.transport_from_locality END
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
GRANT EXECUTE ON FUNCTION public.get_activity_participants(uuid) TO authenticated;

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
    -- 00490 (Scott): where the cars leave from is what makes someone join
    -- (« a car leaves from my town »), so every viewer of the outing sees the
    -- places — never WHO leaves from where (per-person transport is masked
    -- for non-members in get_activity_participants). Never across a block.
    -- 00521: villages only (never the typed text, often an address).
    array_agg(DISTINCT p.transport_from_locality) FILTER (
      WHERE p.transport_from_locality IS NOT NULL
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
      -- 00521: a pickup point goes to the driver, the passenger and the organiser only.
      CASE WHEN v_user_id IN (sr.driver_id, sr.requester_id, v_creator) THEN sr.pickup_from END,
      CASE WHEN v_user_id IN (sr.driver_id, sr.requester_id, v_creator) THEN sr.requested_pickup_at END
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


CREATE OR REPLACE FUNCTION public.get_user_sport_levels(p_user_id uuid)
 RETURNS TABLE(sport_key text, dots smallint, last_at timestamp with time zone, first_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH completed AS (
    SELECT s.key AS sport_key, a.level AS level, a.starts_at AS at
    FROM participations p
    JOIN activities a ON a.id = p.activity_id
    JOIN sports s ON s.id = a.sport_id
    WHERE p.user_id = p_user_id
      AND p.status = 'accepted'
      AND p.confirmed_present = true /* 00521: validated presence only */  -- 00495 (PR-7)
      AND a.status = 'completed'
      AND a.deleted_at IS NULL  -- 00495
      AND NOT private.user_is_suspended(p_user_id)  -- 00503 (DX-3)
      AND auth.uid() IS NOT NULL AND NOT private.user_is_suspended(auth.uid())  -- 00520 (ID-9)
      -- 00419 M3 : rideau démo.
      AND NOT (
        EXISTS (SELECT 1 FROM users du WHERE du.id = p_user_id AND du.is_demo = true)
        AND NOT demo_content_visible()
      )
  ),
  agg AS (
    SELECT
      completed.sport_key,
      count(*) AS total,
      count(*) FILTER (
        WHERE completed.level IN ('intermédiaire', 'intermediate', 'avancé', 'advanced', 'expert')
      ) AS at_intermediate,
      count(*) FILTER (
        WHERE completed.level IN ('avancé', 'advanced', 'expert')
      ) AS at_advanced,
      count(*) FILTER (WHERE completed.level = 'expert') AS at_expert,
      max(completed.at) AS last_at,
      min(completed.at) AS first_at
    FROM completed
    GROUP BY completed.sport_key
  )
  SELECT
    agg.sport_key,
    (CASE
      WHEN agg.at_expert >= 3 THEN 4
      WHEN agg.at_advanced >= 5 THEN 3
      WHEN agg.at_intermediate >= 3 THEN 2
      WHEN agg.total >= 1 THEN 1
      ELSE 0
    END)::SMALLINT AS dots,
    -- 00499 (DX-4): month only — an exact time could date a private outing.
    date_trunc('month', agg.last_at),
    date_trunc('month', agg.first_at)
  FROM agg
  WHERE agg.total > 0;
$function$;

CREATE OR REPLACE FUNCTION public.get_user_trophies(p_user_id uuid)
 RETURNS TABLE(category text, sport_key text, count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller UUID;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_caller AND suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  -- 00419 M3 : rideau démo.
  -- 00516 (DX-3): a suspended account reveals nothing.
  IF private.user_is_suspended(p_user_id) THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users du WHERE du.id = p_user_id AND du.is_demo = true)
     AND NOT demo_content_visible() THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT 'joined'::text, NULL::text,
    (SELECT count(*)::int
     FROM participations par
     JOIN activities a ON a.id = par.activity_id
     WHERE par.user_id = p_user_id
       AND par.status = 'accepted'
       AND par.confirmed_present = true /* 00521: validated presence only */  -- 00491 (PR-7): an absence is not an outing
       AND a.status = 'completed'
       AND a.creator_id != p_user_id
       AND a.deleted_at IS NULL)
  UNION ALL
  SELECT 'created'::text, NULL::text,
    (SELECT count(*)::int
     FROM activities
     WHERE creator_id = p_user_id
       AND status = 'completed'
       AND deleted_at IS NULL
       -- 00521: only an outing whose organiser's presence was validated.
       AND EXISTS (SELECT 1 FROM participations cp
                   WHERE cp.activity_id = activities.id AND cp.user_id = p_user_id
                     AND cp.confirmed_present = true))
  UNION ALL
  SELECT 'sport'::text, s.key::text, count(*)::int
  FROM participations par
  JOIN activities a ON a.id = par.activity_id
  JOIN sports s ON s.id = a.sport_id
  WHERE par.user_id = p_user_id
    AND par.status = 'accepted'
    AND par.confirmed_present = true /* 00521: validated presence only */  -- 00491 (PR-7)
    AND a.status = 'completed'
    AND a.deleted_at IS NULL
  GROUP BY s.key
  HAVING count(*) > 0;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_user_award_aggregates(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH completed AS (
    SELECT
      a.id,
      a.creator_id,
      a.duration,
      s.key AS sport_key,
      s.category
    FROM participations p
    JOIN activities a ON a.id = p.activity_id
    JOIN sports s ON s.id = a.sport_id
    WHERE p.user_id = p_user_id
      AND p.status = 'accepted'
      AND p.confirmed_present = true /* 00521: validated presence only */  -- 00520 (PR-7)
      AND a.status = 'completed'
      AND a.deleted_at IS NULL  -- 00520 (PR-10)
      AND auth.uid() IS NOT NULL AND NOT private.user_is_suspended(auth.uid())  -- 00520 (ID-9)
      AND NOT private.user_is_suspended(p_user_id)  -- 00503 (DX-3)
      -- 00419 M3 : rideau démo.
      AND NOT (
        EXISTS (SELECT 1 FROM users du WHERE du.id = p_user_id AND du.is_demo = true)
        AND NOT demo_content_visible()
      )
  ),
  per_category AS (
    SELECT
      category,
      count(*)::int AS outings,
      count(DISTINCT sport_key)::int AS distinct_sports
    FROM completed
    GROUP BY category
  )
  SELECT jsonb_build_object(
    'joined', (SELECT count(*)::int FROM completed WHERE creator_id IS DISTINCT FROM p_user_id),
    'created', (SELECT count(*)::int FROM completed WHERE creator_id = p_user_id),
    'distinct_sports', (SELECT count(DISTINCT sport_key)::int FROM completed),
    'multi_day_count', (SELECT count(*)::int FROM completed WHERE duration > INTERVAL '1 day'),
    'by_category', COALESCE((
      SELECT jsonb_object_agg(category, jsonb_build_object(
        'outings', outings,
        'distinct_sports', distinct_sports
      )) FROM per_category
    ), '{}'::jsonb)
  );
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

  -- 00499 (DX-3): a suspended account reveals nothing (like public_profiles).
  IF private.user_is_suspended(p_user_id) THEN RETURN; END IF;
  -- 00520 (ID-9): a signed-in, non-suspended caller only.
  IF auth.uid() IS NULL OR private.user_is_suspended(auth.uid()) THEN RETURN; END IF;

  RETURN QUERY
  WITH real_outings AS (
    SELECT a.id, a.creator_id
    FROM participations par
    JOIN activities a ON a.id = par.activity_id
    WHERE par.user_id = p_user_id
      AND par.status = 'accepted'
      AND par.confirmed_present = true /* 00521: validated presence only */
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

CREATE OR REPLACE FUNCTION public.get_discovery_cards()
 RETURNS TABLE(user_id uuid, display_name text, avatar_url text, reliability_tier text, sport_keys text[], levels jsonb, transport_modes text[], radius_km integer, window_start timestamp with time zone, window_end timestamp with time zone, intent text[], distance_km double precision, sorties_count integer, about text, contact_state text, conversation_id uuid, is_demo boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_base GEOGRAPHY;
  v_radius INTEGER;
  v_sports TEXT[];
  v_ws TIMESTAMPTZ;
  v_we TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN; END IF;

  SELECT d.base, d.radius_km, d.sport_keys, d.window_start, d.window_end
    INTO v_base, v_radius, v_sports, v_ws, v_we
  FROM discovery_availabilities d WHERE d.user_id = v_user_id AND d.is_active;
  IF v_base IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT d.user_id, pp.display_name, pp.avatar_url, pp.reliability_tier,
         d.sport_keys, d.levels, d.transport_modes, d.radius_km,
         d.window_start, d.window_end, d.intent,
         -- 00485 (DC-1): whole kilometres, never below 1.
         greatest(1, round(ST_Distance(d.base, v_base) / 1000.0))::float8 AS distance_km,
         -- 00435 (trouvé par Scott) : ce compteur n'exigeait QUE status =
         -- 'accepted' — donc s'inscrire à 200 sorties futures affichait
         -- « 200 sorties » immédiatement, sans qu'aucune ait eu lieu. Et c'est
         -- le chiffre qu'un inconnu lit avant de décider de te contacter. On
         -- applique le même prédicat que get_user_public_stats : sortie
         -- réellement terminée, et présence non démentie.
         (SELECT count(*)::int FROM participations p
          JOIN activities pa ON pa.id = p.activity_id
          WHERE p.user_id = d.user_id
            AND p.status = 'accepted'
            AND p.confirmed_present = true /* 00521: validated presence only */
            AND pa.status = 'completed'
            AND pa.deleted_at IS NULL) AS sorties_count,
         d.about,
         coalesce((
           SELECT CASE
             WHEN c.status = 'active' THEN 'connected'
             WHEN c.request_sender_id = v_user_id THEN 'pending'
             WHEN c.status = 'pending_request' AND c.request_expires_at > NOW() THEN 'pending_received'
             ELSE 'none'
           END
           FROM conversations c
           WHERE c.type = 'dm'
             AND c.user_1 = LEAST(v_user_id, d.user_id)
             AND c.user_2 = GREATEST(v_user_id, d.user_id)
         ), 'none') AS contact_state,
         (
           SELECT c.id FROM conversations c
           WHERE c.type = 'dm' AND c.status = 'active'
             AND c.user_1 = LEAST(v_user_id, d.user_id)
             AND c.user_2 = GREATEST(v_user_id, d.user_id)
         ) AS conversation_id,
         u.is_demo
  FROM discovery_availabilities d
  JOIN users u ON u.id = d.user_id AND u.suspended_at IS NULL
  JOIN public_profiles pp ON pp.id = d.user_id
  WHERE d.is_active
    -- 00494 (BR-5): a dispo whose window is over is no longer offered.
    AND d.window_end > now()
    AND d.user_id <> v_user_id
    AND (d.is_demo = false OR demo_content_visible())
    AND d.sport_keys && v_sports
    AND tstzrange(d.window_start, d.window_end) && tstzrange(v_ws, v_we)
    AND (
         -- 00520 (C1): zones must really meet. « Peu importe » on one side means
         -- the OTHER side's radius must contain it; both « peu importe » match.
         (v_radius IS NULL AND d.radius_km IS NULL)
         OR ST_DWithin(d.base, v_base, (coalesce(v_radius, 0) + coalesce(d.radius_km, 0)) * 1000.0))
    AND NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE (b.blocker_id = v_user_id AND b.blocked_id = d.user_id)
         OR (b.blocker_id = d.user_id AND b.blocked_id = v_user_id))
  -- 00435 : le tri portait sur pp.reliability_score, que la vue public_profiles
  -- force à NULL depuis 00347 (elle ne publie que le palier) → clé de tri
  -- constamment vide, classement dégénéré en distance seule, et ce depuis six
  -- réécritures de cette fonction. On trie sur la table users, déjà jointe
  -- ligne « JOIN users u ». Ce n'est qu'un ORDER BY : aucune colonne
  -- supplémentaire n'est retournée, donc le score brut reste non publié.
  ORDER BY u.reliability_score DESC NULLS LAST, distance_km ASC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.award_badge_progression(p_user_id uuid, p_silent boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count INTEGER;
  v_tier TEXT;
  v_inserted UUID;
  v_label TEXT;
BEGIN
  -- Joined activities (where the user wasn't the creator)
  SELECT count(*) INTO v_count
  FROM participations par
  JOIN activities a ON a.id = par.activity_id
  WHERE par.user_id = p_user_id
    AND par.status = 'accepted'
    AND par.confirmed_present = true /* 00521: validated presence only */  -- 00495 (PR-7)
    AND a.status = 'completed'
    AND a.creator_id != p_user_id
    AND a.deleted_at IS NULL;
  v_tier := badge_tier_for(v_count);
  IF v_tier IS NOT NULL THEN
    INSERT INTO user_badge_progression (user_id, category, sport_key, tier_key)
    VALUES (p_user_id, 'joined', NULL, v_tier)
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_inserted;
    IF v_inserted IS NOT NULL AND NOT p_silent THEN
      v_label := badge_label_fr('joined', v_tier);
      PERFORM create_notification(
        p_user_id,
        'badge_unlocked',
        'Nouveau badge !',
        'Tu es maintenant ' || v_label,
        jsonb_build_object('category', 'joined', 'tier', v_tier, 'params', jsonb_build_object('label', v_label))
      );
    END IF;
  END IF;
  v_inserted := NULL;

  -- Created activities
  SELECT count(*) INTO v_count
  FROM activities
  WHERE creator_id = p_user_id
    AND status = 'completed'
    AND deleted_at IS NULL;
  v_tier := badge_tier_for(v_count);
  IF v_tier IS NOT NULL THEN
    INSERT INTO user_badge_progression (user_id, category, sport_key, tier_key)
    VALUES (p_user_id, 'created', NULL, v_tier)
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_inserted;
    IF v_inserted IS NOT NULL AND NOT p_silent THEN
      v_label := badge_label_fr('created', v_tier);
      PERFORM create_notification(
        p_user_id,
        'badge_unlocked',
        'Nouveau badge !',
        'Tu es maintenant ' || v_label,
        jsonb_build_object('category', 'created', 'tier', v_tier, 'params', jsonb_build_object('label', v_label))
      );
    END IF;
  END IF;
END;
$function$;

-- ---------- Décision 1 : pas de sortie commune entre deux personnes qui se bloquent ----------
CREATE OR REPLACE FUNCTION private.check_shared_outing_block()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status NOT IN ('accepted', 'pending') THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = NEW.status THEN RETURN NEW; END IF;
  IF auth.uid() IS NULL THEN RETURN NEW; END IF;  -- system writes (demo seeding)
  IF EXISTS (SELECT 1 FROM activities a WHERE a.id = NEW.activity_id AND a.is_demo) THEN RETURN NEW; END IF;
  -- Someone already in the outing (organiser included) who BLOCKED the newcomer:
  -- generic refusal (never tell who blocks whom).
  IF EXISTS (
    SELECT 1 FROM blocked_users b
    WHERE b.blocked_id = NEW.user_id
      AND (b.blocker_id IN (SELECT p.user_id FROM participations p
                            WHERE p.activity_id = NEW.activity_id AND p.status = 'accepted' AND p.user_id <> NEW.user_id)
           OR b.blocker_id = (SELECT a.creator_id FROM activities a WHERE a.id = NEW.activity_id))
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- The newcomer blocked someone already in it: they know it, say it.
  IF EXISTS (
    SELECT 1 FROM blocked_users b
    WHERE b.blocker_id = NEW.user_id
      AND b.blocked_id IN (SELECT p.user_id FROM participations p
                           WHERE p.activity_id = NEW.activity_id AND p.status = 'accepted' AND p.user_id <> NEW.user_id)
  ) THEN
    RAISE EXCEPTION 'junto.blocked_member_present';
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION private.check_shared_outing_block() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_participations_shared_block ON participations;
CREATE TRIGGER trg_participations_shared_block BEFORE INSERT OR UPDATE OF status ON participations
  FOR EACH ROW EXECUTE FUNCTION private.check_shared_outing_block();

-- ---------- Décision 5 : plafond de fichiers par compte ----------
CREATE OR REPLACE FUNCTION private.storage_object_quota()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_folder TEXT := (storage.foldername(NEW.name))[1];
  v_cap INTEGER := CASE NEW.bucket_id WHEN 'avatars' THEN 10 WHEN 'pro-photos' THEN 200 WHEN 'channel-photos' THEN 50 ELSE NULL END;
BEGIN
  IF v_cap IS NULL OR auth.uid() IS NULL THEN RETURN NEW; END IF;
  PERFORM pg_advisory_xact_lock(hashtext('storage:' || NEW.bucket_id || ':' || coalesce(v_folder, '')));
  IF (SELECT count(*) FROM storage.objects o
      WHERE o.bucket_id = NEW.bucket_id AND (storage.foldername(o.name))[1] = v_folder) >= v_cap THEN
    RAISE EXCEPTION 'junto.storage_quota';
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION private.storage_object_quota() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS junto_storage_object_quota ON storage.objects;
CREATE TRIGGER junto_storage_object_quota BEFORE INSERT ON storage.objects
  FOR EACH ROW EXECUTE FUNCTION private.storage_object_quota();

-- ---------- Décision 6 : l'admin est prévenu quand une vitrine approuvée change de nom ----------
CREATE OR REPLACE FUNCTION private.notify_pro_renamed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin UUID;
BEGIN
  IF NEW.status <> 'approved' OR NEW.display_name IS NOT DISTINCT FROM OLD.display_name THEN RETURN NULL; END IF;
  FOR v_admin IN SELECT id FROM users WHERE is_admin AND suspended_at IS NULL LOOP
    PERFORM create_notification(v_admin, 'pro_renamed', 'Vitrine pro renommée',
      sanitize_notif_text(coalesce(OLD.display_name, '?')) || ' → ' || sanitize_notif_text(coalesce(NEW.display_name, '?')),
      jsonb_build_object('pro_id', NEW.user_id,
        'params', jsonb_build_object('old', sanitize_notif_text(coalesce(OLD.display_name, '?')), 'new', sanitize_notif_text(coalesce(NEW.display_name, '?')))));
  END LOOP;
  RETURN NULL;
END;
$function$;
REVOKE ALL ON FUNCTION private.notify_pro_renamed() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_pro_profiles_renamed ON pro_profiles;
CREATE TRIGGER trg_pro_profiles_renamed AFTER UPDATE OF display_name ON pro_profiles
  FOR EACH ROW EXECUTE FUNCTION private.notify_pro_renamed();
