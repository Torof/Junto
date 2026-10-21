-- ============================================================================
-- 00474 — Contre-audit des correctifs d'octobre (phases 2-5). Base = dernières
-- définitions (migrations 00469-00473, identiques au live, + live pour
-- create_gpx_trace / edit_message / consume_trace_elevation_quota).
--
-- F1 consume_trace_elevation_quota ne compte plus les lignes de points (00471
--    divisait de fait le quota d'appels par deux → D+ en direct coupé).
-- F3 distance déduite < 0,05 km arrondie à 0,0 par numeric(6,1) → test sur la
--    valeur arrondie (create_activity, update_activity_trace).
-- F4 update_pro_profile : trim APRÈS retrait des balises (« <b>  </b> » ne
--    devient plus un nom fait d'espaces).
-- F5 edit_message garde la première version dans message_original_content
--    (table interne, aucun grant) ; l'archive de retrait de contact l'inclut.
-- F6a revoke_contact_qr_tokens(p_token) : ne révoque que le jeton affiché.
-- F8 create_gpx_trace passe par trace_geojson_ok.
-- F9 motif d'annulation borné à 300.
-- ============================================================================

CREATE TABLE IF NOT EXISTS message_original_content (
  message_id UUID PRIMARY KEY REFERENCES messages(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  saved_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE message_original_content ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_original_content FORCE ROW LEVEL SECURITY;
REVOKE ALL ON message_original_content FROM PUBLIC, anon, authenticated;

DROP FUNCTION IF EXISTS public.revoke_contact_qr_tokens();
CREATE OR REPLACE FUNCTION public.revoke_contact_qr_tokens(p_token text DEFAULT NULL)
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
  -- Own tokens only. With p_token: just that one (the screen passes the token
  -- it was showing, so a late revoke never kills a fresher token minted by a
  -- quick reopen — counter-audit F6a). Without: every live one.
  UPDATE contact_qr_tokens SET expires_at = now()
  WHERE user_id = v_user_id AND expires_at > now()
    AND (p_token IS NULL OR token = p_token);
END;
$function$;

CREATE OR REPLACE FUNCTION public.consume_trace_elevation_quota()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user UUID;
  v_count INTEGER;
BEGIN
  v_user := auth.uid();
  IF v_user IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user::text || '_trace_elevation'));
  DELETE FROM trace_elevation_calls WHERE user_id = v_user AND called_at < now() - INTERVAL '1 hour';
  -- 00474 (counter-audit F1): only CALL rows (points = 0) count here; the
  -- points rows added by 00471 halved the call quota.
  SELECT count(*) INTO v_count FROM trace_elevation_calls WHERE user_id = v_user AND points = 0;
  IF v_count >= 150 THEN RAISE EXCEPTION 'junto.rate_limited'; END IF;
  INSERT INTO trace_elevation_calls (user_id) VALUES (v_user);
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
      IF round(v_distance_km, 1) <= 0 OR v_distance_km > 9999 THEN v_distance_km := NULL; END IF;
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
          THEN (SELECT CASE WHEN round(d, 1) > 0 AND d <= 9999 THEN d END FROM (SELECT trace_distance_km(p_trace_geojson) AS d) x)
        ELSE distance_km END,
      elevation_gain_m = CASE
        WHEN p_trace_geojson IS NOT NULL AND elevation_gain_m IS NULL
          THEN (SELECT CASE WHEN g > 0 AND g <= 99999 THEN g END FROM (SELECT trace_elevation_gain_m(p_trace_geojson) AS g) x)
        ELSE elevation_gain_m END,
      updated_at = now()
  WHERE id = p_activity_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_pro_profile(p_display_name text DEFAULT NULL::text, p_tagline text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_website text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_instagram text DEFAULT NULL::text, p_facebook text DEFAULT NULL::text, p_primary_lng double precision DEFAULT NULL::double precision, p_primary_lat double precision DEFAULT NULL::double precision, p_primary_location_name text DEFAULT NULL::text, p_company_name text DEFAULT NULL::text, p_real_name text DEFAULT NULL::text, p_clear text[] DEFAULT NULL::text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_existing RECORD;
  v_location_changing BOOLEAN := false;
  v_clear TEXT[] := COALESCE(p_clear, ARRAY[]::TEXT[]);
  v_col TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_existing FROM pro_profiles WHERE user_id = v_user_id FOR UPDATE;
  IF v_existing IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- 00443 B3 : une fois APPROUVÉ, raison sociale et identité sont gelées —
  -- les renvoyer inchangées est permis, les changer passe par nous.
  IF v_existing.status = 'approved' THEN
    IF (p_company_name IS NOT NULL
        AND trim(regexp_replace(p_company_name, '<[^>]*>', '', 'g')) IS DISTINCT FROM v_existing.company_name)
       OR (p_real_name IS NOT NULL
        AND trim(regexp_replace(p_real_name, '<[^>]*>', '', 'g')) IS DISTINCT FROM v_existing.real_name) THEN
      RAISE EXCEPTION 'junto.pro_identity_locked';
    END IF;
  END IF;

  -- 00444 (1) : liste blanche des colonnes vidables. ≤ 7 entrées, toutes connues.
  IF array_length(v_clear, 1) > 7 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  FOREACH v_col IN ARRAY v_clear LOOP
    IF v_col IS NULL OR v_col NOT IN ('tagline', 'description', 'website', 'email', 'phone', 'instagram', 'facebook') THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END LOOP;

  IF p_primary_lng IS NOT NULL OR p_primary_lat IS NOT NULL THEN
    IF p_primary_lng IS NULL OR p_primary_lat IS NULL OR p_primary_location_name IS NULL THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF p_primary_lng < -180 OR p_primary_lng > 180 OR p_primary_lat < -90 OR p_primary_lat > 90 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    -- 00444 (2) : cooldown seulement pour une enseigne publique (approved).
    IF v_existing.status = 'approved'
       AND v_existing.last_location_change_at > now() - INTERVAL '30 days' THEN
      RAISE EXCEPTION 'junto.pro_location_cooldown';
    END IF;
    v_location_changing := true;
  END IF;

  IF p_display_name IS NOT NULL AND (char_length(trim(regexp_replace(p_display_name, '<[^>]*>', '', 'g'))) < 1 OR char_length(p_display_name) > 100) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_company_name IS NOT NULL AND (char_length(trim(regexp_replace(p_company_name, '<[^>]*>', '', 'g'))) < 2 OR char_length(p_company_name) > 120) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_real_name IS NOT NULL AND (char_length(trim(regexp_replace(p_real_name, '<[^>]*>', '', 'g'))) < 2 OR char_length(p_real_name) > 120) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_tagline IS NOT NULL AND char_length(p_tagline) > 120 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_description IS NOT NULL AND char_length(p_description) > 2000 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_website IS NOT NULL AND char_length(p_website) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_email IS NOT NULL AND char_length(p_email) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_phone IS NOT NULL AND char_length(p_phone) > 30 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_instagram IS NOT NULL AND char_length(p_instagram) > 100 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_facebook IS NOT NULL AND char_length(p_facebook) > 200 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_primary_location_name IS NOT NULL AND (char_length(trim(regexp_replace(p_primary_location_name, '<[^>]*>', '', 'g'))) < 1 OR char_length(p_primary_location_name) > 200) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE pro_profiles SET
    display_name = COALESCE(trim(regexp_replace(p_display_name, '<[^>]*>', '', 'g')), display_name),
    company_name = CASE WHEN p_company_name IS NOT NULL THEN trim(regexp_replace(p_company_name, '<[^>]*>', '', 'g')) ELSE company_name END,
    real_name = CASE WHEN p_real_name IS NOT NULL THEN trim(regexp_replace(p_real_name, '<[^>]*>', '', 'g')) ELSE real_name END,
    tagline = CASE WHEN 'tagline' = ANY(v_clear) THEN NULL
                   WHEN p_tagline IS NOT NULL THEN trim(regexp_replace(p_tagline, '<[^>]*>', '', 'g')) ELSE tagline END,
    description = CASE WHEN 'description' = ANY(v_clear) THEN NULL
                       WHEN p_description IS NOT NULL THEN trim(regexp_replace(p_description, '<[^>]*>', '', 'g')) ELSE description END,
    website = CASE WHEN 'website' = ANY(v_clear) THEN NULL ELSE COALESCE(p_website, website) END,
    email = CASE WHEN 'email' = ANY(v_clear) THEN NULL ELSE COALESCE(p_email, email) END,
    phone = CASE WHEN 'phone' = ANY(v_clear) THEN NULL ELSE COALESCE(p_phone, phone) END,
    instagram = CASE WHEN 'instagram' = ANY(v_clear) THEN NULL ELSE COALESCE(p_instagram, instagram) END,
    facebook = CASE WHEN 'facebook' = ANY(v_clear) THEN NULL ELSE COALESCE(p_facebook, facebook) END,
    primary_lng = CASE WHEN v_location_changing THEN p_primary_lng ELSE primary_lng END,
    primary_lat = CASE WHEN v_location_changing THEN p_primary_lat ELSE primary_lat END,
    primary_location = CASE WHEN v_location_changing
                            THEN ST_SetSRID(ST_MakePoint(p_primary_lng, p_primary_lat), 4326)::geography
                            ELSE primary_location END,
    primary_location_name = CASE WHEN v_location_changing THEN trim(regexp_replace(p_primary_location_name, '<[^>]*>', '', 'g')) ELSE primary_location_name END,
    last_location_change_at = CASE WHEN v_location_changing THEN now() ELSE last_location_change_at END
  WHERE user_id = v_user_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_activity(p_activity_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_participant RECORD;
  v_clean_reason TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00472/00474 (audit L11, F9): bounded to 300 — copied into every participant's
  -- notification, twice in the push payload (body + params), under Expo's 4 KB.
  v_clean_reason := left(NULLIF(trim(coalesce(p_reason, '')), ''), 300);
  IF v_clean_reason IS NULL OR char_length(v_clean_reason) < 3 THEN
    RAISE EXCEPTION 'junto.cancel_reason_invalid';
  END IF;

  SELECT id, creator_id, status, title
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id
  FOR UPDATE;

  IF v_activity IS NULL OR v_user_id != v_activity.creator_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE activities
  SET status = 'cancelled',
      cancelled_reason = v_clean_reason,
      updated_at = now()
  WHERE id = p_activity_id;

  -- Notify all accepted participants except creator
  FOR v_participant IN
    SELECT user_id FROM participations
    WHERE activity_id = p_activity_id
      AND status IN ('accepted', 'pending')
      AND user_id != v_user_id
  LOOP
    PERFORM create_notification(
      v_participant.user_id,
      'activity_cancelled',
      'Sortie annulée',
      CASE WHEN coalesce(v_clean_reason, '') = '' THEN '« ' || v_activity.title || ' »'
           ELSE '« ' || v_activity.title || ' » — ' || v_clean_reason END,
      jsonb_build_object('activity_id', p_activity_id,
        'variant', CASE WHEN coalesce(v_clean_reason, '') = '' THEN 'no_reason' ELSE NULL END,
        'params', jsonb_build_object('title', v_activity.title, 'reason', coalesce(v_clean_reason, '')))
    );
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_gpx_trace(p_name text, p_geojson jsonb)
 RETURNS gpx_traces
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_name TEXT;
  v_geom geometry;
  v_distance_km NUMERIC(7,2);
  v_elevation_gain_m INTEGER;
  v_count INTEGER;
  v_row gpx_traces;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_name := trim(p_name);
  IF char_length(v_name) < 1 OR char_length(v_name) > 80 THEN
    RAISE EXCEPTION 'junto.trace_name_invalid';
  END IF;

  -- 00474 (counter-audit F8): same shape/size gate as the activity paths.
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

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_gpx_trace'));
  SELECT count(*) INTO v_count FROM gpx_traces WHERE user_id = v_user_id;
  IF v_count >= 50 THEN
    RAISE EXCEPTION 'junto.trace_quota_reached';
  END IF;

  v_distance_km := round((ST_Length(v_geom::geography) / 1000)::numeric, 2);
  v_elevation_gain_m := trace_elevation_gain_m(p_geojson);

  INSERT INTO gpx_traces (user_id, name, geojson, distance_km, elevation_gain_m, created_at, updated_at)
  VALUES (v_user_id, v_name, p_geojson, v_distance_km, v_elevation_gain_m, now(), now())
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$function$;

CREATE OR REPLACE FUNCTION public.edit_message(p_message_id uuid, p_content text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_conv_id UUID;
  v_type TEXT;
  v_activity_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_content IS NULL OR char_length(trim(p_content)) < 1 OR char_length(p_content) > 2000 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT c.id, c.type, c.activity_id INTO v_conv_id, v_type, v_activity_id
  FROM messages m JOIN conversations c ON c.id = m.conversation_id
  WHERE m.id = p_message_id AND m.sender_id = v_user_id
    AND m.deleted_at IS NULL AND m.metadata IS NULL; -- rich cards not editable
  IF v_conv_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Must still be a member; for activity messages the activity must be alive
  -- (wall edit parity 00177).
  IF NOT private.is_conversation_member(v_conv_id, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_type = 'activity' AND NOT EXISTS (
    SELECT 1 FROM activities a WHERE a.id = v_activity_id
      AND a.deleted_at IS NULL AND a.status IN ('published', 'in_progress')
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- 00474 (counter-audit F5): keep the first version for moderation (internal
  -- table, no client grant) — an edit can no longer launder a thread.
  INSERT INTO message_original_content (message_id, content)
  SELECT id, content FROM messages WHERE id = p_message_id
  ON CONFLICT (message_id) DO NOTHING;

  UPDATE messages SET content = trim(p_content), edited_at = now()
  WHERE id = p_message_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.remove_connection(p_other_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_conv RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Only a genuine social connection can be removed here — never a transport /
  -- request_reply logistics thread.
  SELECT id, user_1, user_2 INTO v_conv
  FROM conversations
  WHERE type = 'dm'
    AND status = 'active'
    AND initiated_from IN ('profile', 'discovery', 'invite')
    AND ((user_1 = v_user_id AND user_2 = p_other_user_id)
      OR (user_1 = p_other_user_id AND user_2 = v_user_id));
  IF v_conv.id IS NULL THEN RETURN; END IF;

  -- A live carpool between the pair would be stranded (accepted seat + reservation)
  -- if we deleted the shared thread. Ask the user to settle it first.
  IF EXISTS (
    SELECT 1 FROM seat_requests s
    WHERE s.status IN ('pending', 'accepted')
      AND ((s.driver_id = v_user_id AND s.requester_id = p_other_user_id)
        OR (s.driver_id = p_other_user_id AND s.requester_id = v_user_id))
  ) THEN
    RAISE EXCEPTION 'junto.carpool_active';
  END IF;

  -- 00469 (audit M4): keep the thread for moderation before it disappears.
  INSERT INTO contact_removal_archive (conversation_id, user_1, user_2, removed_by, messages)
  SELECT v_conv.id, v_conv.user_1, v_conv.user_2, v_user_id,
         COALESCE(jsonb_agg(jsonb_build_object(
           'id', m.id, 'sender_id', m.sender_id, 'content', m.content, 'created_at', m.created_at,
           'edited_at', m.edited_at, 'original_content', o.content
         ) ORDER BY m.created_at), '[]'::jsonb)
  FROM messages m LEFT JOIN message_original_content o ON o.message_id = m.id
  WHERE m.conversation_id = v_conv.id;

  DELETE FROM conversations WHERE id = v_conv.id;
END;
$function$;

REVOKE ALL ON FUNCTION public.revoke_contact_qr_tokens(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revoke_contact_qr_tokens(text) TO authenticated;
