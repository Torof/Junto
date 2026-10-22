-- « Tu y étais ? » — self-declared presence on outings WITHOUT presence
-- validation (Scott 2026-10-23). At completion every accepted participant is
-- asked; for 48 h after the end each answers for themself only:
--   yes / no answer → the outing counts in the public counters,
--   « no »           → it does not (levels, trophies, stats, discovery).
-- Never touches reliability (validated presence only) and never opens the
-- votes on levels / trophies (00497: votes stay with verified presence).

ALTER TABLE public.participations
  ADD COLUMN self_presence text CHECK (self_presence IN ('yes', 'no')),
  ADD COLUMN self_presence_at timestamptz;
GRANT SELECT (self_presence, self_presence_at) ON public.participations TO authenticated;

CREATE OR REPLACE FUNCTION public.declare_my_presence(p_activity_id uuid, p_present boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF private.user_is_suspended(v_user_id) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_present IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT id, status, starts_at, duration, deleted_at, requires_presence
  INTO v_activity FROM activities WHERE id = p_activity_id;
  IF v_activity.id IS NULL OR v_activity.status <> 'completed' OR v_activity.deleted_at IS NOT NULL
     OR v_activity.requires_presence IS TRUE THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM participations
                 WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF now() > v_activity.starts_at + v_activity.duration + INTERVAL '48 hours' THEN
    RAISE EXCEPTION 'junto.presence_declare_closed';
  END IF;

  UPDATE participations
  SET self_presence = CASE WHEN p_present THEN 'yes' ELSE 'no' END, self_presence_at = now()
  WHERE activity_id = p_activity_id AND user_id = v_user_id;

  IF p_present THEN
    PERFORM award_badge_progression(v_user_id, true);
  ELSE
    -- A milestone reached only thanks to this outing is taken back.
    DELETE FROM user_badge_progression b
    WHERE b.user_id = v_user_id AND b.category IN ('joined', 'created')
      AND array_position(ARRAY['bronze', 'silver', 'gold'], b.tier_key) > coalesce(array_position(ARRAY['bronze', 'silver', 'gold'],
            badge_tier_for(CASE b.category
              WHEN 'joined' THEN (SELECT count(*)::int FROM participations par JOIN activities a ON a.id = par.activity_id
                                  WHERE par.user_id = v_user_id AND par.status = 'accepted' AND a.status = 'completed'
                                    AND a.creator_id != v_user_id AND a.deleted_at IS NULL
                                    AND par.self_presence IS DISTINCT FROM 'no')
              ELSE (SELECT count(*)::int FROM activities a WHERE a.creator_id = v_user_id AND a.status = 'completed'
                      AND a.deleted_at IS NULL
                      AND NOT EXISTS (SELECT 1 FROM participations sp WHERE sp.activity_id = a.id
                                        AND sp.user_id = v_user_id AND sp.self_presence = 'no'))
            END)), 0);
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.declare_my_presence(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.declare_my_presence(uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_user_sport_levels(p_user_id uuid)
 RETURNS TABLE(sport_key text, dots smallint, last_at timestamp with time zone, first_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  WITH completed AS (
    SELECT s.key AS sport_key, private.level_tier(s.key, a.level) AS tier, a.starts_at AS at
    FROM participations p
    JOIN activities a ON a.id = p.activity_id
    JOIN sports s ON s.id = a.sport_id
    WHERE p.user_id = p_user_id
      AND p.status = 'accepted'
      -- 00528: every completed outing counts (presence feeds reliability only)
      AND a.status = 'completed'
      AND p.self_presence IS DISTINCT FROM 'no'  -- 00543: « Non, je n'y étais pas » retire la sortie
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
        WHERE completed.tier >= 1  -- 00525: app values (« Intermédiaire », « 6b »…)
      ) AS at_intermediate,
      count(*) FILTER (
        WHERE completed.tier >= 2
      ) AS at_advanced,
      count(*) FILTER (WHERE completed.tier = 3) AS at_expert,
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

CREATE OR REPLACE FUNCTION public.get_user_award_aggregates(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
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
      -- 00528: every completed outing counts (presence feeds reliability only)
      AND a.status = 'completed'
      AND p.self_presence IS DISTINCT FROM 'no'  -- 00543: « Non, je n'y étais pas » retire la sortie
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
 SET search_path TO 'public', 'extensions'
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
      -- 00528: every completed outing counts (presence feeds reliability only)
      AND a.status = 'completed'
      AND par.self_presence IS DISTINCT FROM 'no'  -- 00543: « Non, je n'y étais pas » retire la sortie
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
            -- 00528: every completed outing counts (presence feeds reliability only)
            AND pa.status = 'completed'
            AND p.self_presence IS DISTINCT FROM 'no'  -- 00543: « Non, je n'y étais pas » retire la sortie
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
         ST_DWithin(d.base, v_base, (CASE WHEN v_radius IS NULL AND d.radius_km IS NULL THEN 50  -- 00522 (F7): two « peu importe » = 50 km, not the whole country
           ELSE coalesce(v_radius, 0) + coalesce(d.radius_km, 0) END) * 1000.0))
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

CREATE OR REPLACE FUNCTION public.get_user_trophies(p_user_id uuid)
 RETURNS TABLE(category text, sport_key text, count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
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
       -- 00528: every completed outing counts (presence feeds reliability only)
       AND a.status = 'completed'
       AND par.self_presence IS DISTINCT FROM 'no'  -- 00543: « Non, je n'y étais pas » retire la sortie
       AND a.creator_id != p_user_id
       AND a.deleted_at IS NULL)
  UNION ALL
  SELECT 'created'::text, NULL::text,
    (SELECT count(*)::int
     FROM activities
     WHERE creator_id = p_user_id
       AND status = 'completed'
       AND deleted_at IS NULL
       AND NOT EXISTS (SELECT 1 FROM participations sp WHERE sp.activity_id = activities.id AND sp.user_id = p_user_id AND sp.self_presence = 'no')  -- 00543: « Non, je n'y étais pas » retire la sortie
       -- 00528: every completed outing counts (presence feeds reliability only)
    )
  UNION ALL
  SELECT 'sport'::text, s.key::text, count(*)::int
  FROM participations par
  JOIN activities a ON a.id = par.activity_id
  JOIN sports s ON s.id = a.sport_id
  WHERE par.user_id = p_user_id
    AND par.status = 'accepted'
    -- 00528: every completed outing counts (presence feeds reliability only)
    AND a.status = 'completed'
    AND par.self_presence IS DISTINCT FROM 'no'  -- 00543: « Non, je n'y étais pas » retire la sortie
    AND a.deleted_at IS NULL
  GROUP BY s.key
  HAVING count(*) > 0;
END;
$function$;

CREATE OR REPLACE FUNCTION public.award_badge_progression(p_user_id uuid, p_silent boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
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
    -- 00528: every completed outing counts (presence feeds reliability only)
    AND a.status = 'completed'
    AND par.self_presence IS DISTINCT FROM 'no'  -- 00543: « Non, je n'y étais pas » retire la sortie
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
    AND deleted_at IS NULL
    AND NOT EXISTS (SELECT 1 FROM participations sp WHERE sp.activity_id = activities.id AND sp.user_id = p_user_id AND sp.self_presence = 'no')  -- 00543: « Non, je n'y étais pas » retire la sortie
    -- 00528: every completed outing counts (presence feeds reliability only)
    ;
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

CREATE OR REPLACE FUNCTION public.on_activity_completed_award_badges()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_participant RECORD;
BEGIN
  IF NEW.status = 'completed' AND (OLD.status IS DISTINCT FROM NEW.status) THEN
    FOR v_participant IN
      SELECT user_id FROM participations
      WHERE activity_id = NEW.id AND status = 'accepted'
    LOOP
      -- Badge progression always (a solo creator still created an outing)
      PERFORM award_badge_progression(v_participant.user_id, FALSE);
    END LOOP;
    -- 00543: sans validation de présence, chacun dit s'il y était (48 h).
    IF NEW.requires_presence IS NOT TRUE AND NOT NEW.is_demo AND NEW.deleted_at IS NULL
       AND now() < NEW.starts_at + NEW.duration + INTERVAL '48 hours' THEN
      FOR v_participant IN
        SELECT user_id FROM participations
        WHERE activity_id = NEW.id AND status = 'accepted'
      LOOP
        PERFORM create_notification(
          v_participant.user_id,
          'presence_self_declare',
          'Tu y étais ?',
          '« ' || NEW.title || ' » — dis-le en un geste, tu as 48 h.',
          jsonb_build_object('activity_id', NEW.id, 'params', jsonb_build_object('title', NEW.title))
        );
      END LOOP;
    END IF;
    -- rate_participants n'est PLUS émis ici (00427) : la fenêtre de vote
    -- n'ouvre qu'à fin+15 min — l'émission vit dans notify_rate_participants,
    -- appelée par les balayages une fois la fenêtre réellement ouverte.
  END IF;
  RETURN NEW;
END;
$function$;
