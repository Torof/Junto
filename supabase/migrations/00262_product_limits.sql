-- Migration 00262: product limits, decided 2026-06-11 (session limites &
-- monétisation — voir DECISIONS.md).
--
-- create_activity :
--   - cap anti-abus journalier 20 → 10/24h (aucun humain légitime n'en
--     crée 10 par jour)
--   - NOUVEAU cap mensuel 15/30 jours — borne le rayon de dégâts d'un
--     compte spammeur (10/jour × 30 = 300 pins sinon) ; la suspension
--     reste l'arme réelle, ceci réduit ce qu'un compte peut faire avant
--     d'être signalé. Distinction clé : PARTICIPER à 40 sorties/mois
--     est un gros mois de sport ; en CRÉER 15+ n'arrive à aucun humain
--     (l'animateur de club type plafonne vers 12). Ratchet : relevable
--     sans douleur si un vrai cas apparaît.
--   - NOUVEAU horizon starts_at ≤ 6 mois — le junk daté dans le passé
--     s'auto-expire (cron) mais le junk daté loin dans le futur restait
--     'published' indéfiniment. Personne ne planifie une sortie casual
--     à plus de 6 mois.
--   - Gate premium private_link DÉSORMAIS CÔTÉ DB — il n'existait que
--     dans l'UI (step3.tsx), en violation de la règle maison "business
--     rules enforced at database level". Sans effet aujourd'hui (tout
--     le monde est premium via 00051) ; réel le jour où le tier free
--     réapparaît. + whitelist explicite des modes de visibilité.
--
-- create_pro_offering :
--   - cap catalogue 50 → 12. Les pins RA sont permanents (ils
--     s'accumulent, contrairement aux UA qui expirent) ; 12 couvre le
--     cas typique (école kayak 5-15 sections, bureau des guides ~10-30
--     dont on veut le best-of) et force la curation. Un cap se relève
--     sans douleur, jamais l'inverse.

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
  p_visibility TEXT DEFAULT 'public',
  p_requires_presence BOOLEAN DEFAULT TRUE,
  p_objective_lng FLOAT DEFAULT NULL,
  p_objective_lat FLOAT DEFAULT NULL,
  p_objective_name TEXT DEFAULT NULL,
  p_distance_km NUMERIC DEFAULT NULL,
  p_elevation_gain_m INTEGER DEFAULT NULL,
  p_start_name TEXT DEFAULT NULL,
  p_trace_geojson JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_tier TEXT;
  v_is_admin BOOLEAN;
  v_daily_count INTEGER;
  v_monthly_count INTEGER;
  v_activity_id UUID;
  v_title TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_title := trim(p_title);
  IF char_length(v_title) < 3 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF p_starts_at IS NULL OR p_starts_at <= NOW() THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Horizon: future-dated junk would otherwise stay 'published' forever.
  IF p_starts_at > NOW() + INTERVAL '6 months' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_max_participants IS NOT NULL AND (p_max_participants < 2 OR p_max_participants > 50) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_visibility NOT IN ('public', 'approval', 'private_link', 'private_link_approval') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_create_activity'));

  SELECT tier, coalesce(is_admin, FALSE) INTO v_tier, v_is_admin
  FROM users WHERE id = v_user_id;

  -- Private activities are a premium capability — enforced here, not
  -- just in the create-flow UI (mig 00262; was client-side only).
  IF p_visibility IN ('private_link', 'private_link_approval')
     AND v_tier NOT IN ('premium', 'pro') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT v_is_admin THEN
    SELECT count(*) INTO v_daily_count
    FROM activities
    WHERE creator_id = v_user_id AND created_at > NOW() - INTERVAL '1 day';

    IF v_daily_count >= 10 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

    SELECT count(*) INTO v_monthly_count
    FROM activities
    WHERE creator_id = v_user_id AND created_at > NOW() - INTERVAL '30 days';

    IF v_monthly_count >= 15 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  INSERT INTO activities (
    creator_id, sport_id, title, description, level,
    max_participants, location_start, location_meeting, location_end,
    location_objective, objective_name, start_name,
    distance_km, elevation_gain_m,
    starts_at, duration, visibility, requires_presence,
    trace_geojson,
    status, created_at, updated_at
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
    CASE WHEN p_objective_lng IS NOT NULL AND p_objective_lat IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_objective_lng, p_objective_lat), 4326)::geography
      ELSE NULL END,
    CASE WHEN p_objective_name IS NOT NULL AND char_length(trim(p_objective_name)) > 0
      THEN trim(p_objective_name) ELSE NULL END,
    CASE WHEN p_start_name IS NOT NULL AND char_length(trim(p_start_name)) > 0
      THEN trim(p_start_name) ELSE NULL END,
    p_distance_km,
    p_elevation_gain_m,
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
$$;

-- ============================================================================
-- create_pro_offering — catalogue cap 50 → 12 (body otherwise identical
-- to 00249)
-- ============================================================================
CREATE OR REPLACE FUNCTION create_pro_offering(
  p_sport_id UUID,
  p_title TEXT,
  p_description TEXT,
  p_level TEXT,
  p_location_lng FLOAT,
  p_location_lat FLOAT,
  p_location_name TEXT,
  p_duration TEXT DEFAULT NULL,
  p_max_participants INTEGER DEFAULT NULL,
  p_schedule_text TEXT DEFAULT NULL,
  p_distance_km NUMERIC DEFAULT NULL,
  p_elevation_gain_m INTEGER DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_tier TEXT;
  v_count INTEGER;
  v_offering_id UUID;
  v_clean_title TEXT;
  v_clean_location_name TEXT;
  v_clean_schedule TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT tier INTO v_tier FROM users WHERE id = v_user_id;
  IF v_tier IS DISTINCT FROM 'pro' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_title := trim(p_title);
  IF char_length(v_clean_title) < 3 OR char_length(v_clean_title) > 100 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_description IS NULL OR char_length(p_description) > 2000 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_level IS NULL OR char_length(trim(p_level)) < 1 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_location_name := trim(p_location_name);
  IF char_length(v_clean_location_name) < 1 OR char_length(v_clean_location_name) > 100 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_location_lng IS NULL OR p_location_lat IS NULL
     OR p_location_lng < -180 OR p_location_lng > 180
     OR p_location_lat < -90 OR p_location_lat > 90 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_max_participants IS NOT NULL AND (p_max_participants < 1 OR p_max_participants > 50) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_schedule_text IS NOT NULL THEN
    v_clean_schedule := trim(p_schedule_text);
    IF char_length(v_clean_schedule) > 100 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF char_length(v_clean_schedule) = 0 THEN
      v_clean_schedule := NULL;
    END IF;
  END IF;

  IF p_distance_km IS NOT NULL AND (p_distance_km <= 0 OR p_distance_km > 9999) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_elevation_gain_m IS NOT NULL AND (p_elevation_gain_m <= 0 OR p_elevation_gain_m > 99999) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('create_offering:' || v_user_id::text));

  SELECT count(*) INTO v_count
  FROM pro_offerings
  WHERE pro_id = v_user_id;

  -- 12: covers the typical catalogue, forces curation, and keeps the
  -- permanent-pin density on the map under control (RA pins accumulate,
  -- UA pins expire). Raise later if real pros ask — never lower.
  IF v_count >= 12 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  INSERT INTO pro_offerings (
    pro_id, sport_id, title, description, level,
    location, location_name,
    duration, max_participants, schedule_text,
    distance_km, elevation_gain_m,
    created_at, updated_at
  ) VALUES (
    v_user_id, p_sport_id, v_clean_title, p_description, p_level,
    ST_SetSRID(ST_MakePoint(p_location_lng, p_location_lat), 4326)::geography,
    v_clean_location_name,
    CASE WHEN p_duration IS NOT NULL THEN p_duration::interval ELSE NULL END,
    p_max_participants,
    v_clean_schedule,
    p_distance_km,
    p_elevation_gain_m,
    now(), now()
  ) RETURNING id INTO v_offering_id;

  RETURN v_offering_id;
END;
$$;
