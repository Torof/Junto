-- 00500 — 00499 suite : le type de signalement « canal » est admis par la
-- contrainte de la table ; borne du rayon d'alerte alignée sur sa contrainte (5-200 km).

ALTER TABLE reports DROP CONSTRAINT reports_target_type_check;
ALTER TABLE reports ADD CONSTRAINT reports_target_type_check CHECK (target_type = ANY (ARRAY[
  'user', 'activity', 'wall_message', 'private_message', 'pro_review', 'offering_review', 'message', 'group', 'channel']));

CREATE OR REPLACE FUNCTION public.create_alert(p_lng double precision, p_lat double precision, p_radius_km integer, p_sport_key text DEFAULT NULL::text, p_levels text[] DEFAULT NULL::text[], p_starts_on date DEFAULT NULL::date, p_ends_on date DEFAULT NULL::date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_alert_count INTEGER;
  v_alert_id UUID;
  v_allowed_levels TEXT[] := ARRAY['débutant', 'intermédiaire', 'avancé', 'expert'];
  v_level TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00499 (DC-6): validated inputs.
  IF p_lng IS NULL OR p_lat IS NULL OR p_lng NOT BETWEEN -180 AND 180 OR p_lat NOT BETWEEN -90 AND 90
     OR p_radius_km IS NULL OR p_radius_km NOT BETWEEN 5 AND 200 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_sport_key IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sports s WHERE s.key = p_sport_key AND s.is_active) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- Serialise the cap.
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_alerts'));

  SELECT count(*) INTO v_alert_count FROM activity_alerts WHERE user_id = v_user_id;
  IF v_alert_count >= 10 THEN
    RAISE EXCEPTION 'junto.alert_limit_reached';
  END IF;

  IF p_levels IS NOT NULL THEN
    IF array_length(p_levels, 1) IS NULL THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    FOREACH v_level IN ARRAY p_levels LOOP
      IF NOT (v_level = ANY(v_allowed_levels)) THEN
        RAISE EXCEPTION 'Operation not permitted';
      END IF;
    END LOOP;
  END IF;

  IF p_starts_on IS NOT NULL AND p_ends_on IS NOT NULL AND p_ends_on < p_starts_on THEN
    RAISE EXCEPTION 'junto.alert_date_invalid';
  END IF;
  IF p_ends_on IS NOT NULL AND p_ends_on < current_date THEN
    RAISE EXCEPTION 'junto.alert_date_invalid';
  END IF;

  INSERT INTO activity_alerts (user_id, sport_key, location, radius_km, levels, starts_on, ends_on, created_at)
  VALUES (
    v_user_id,
    p_sport_key,
    ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
    p_radius_km,
    p_levels,
    p_starts_on,
    p_ends_on,
    now()
  )
  RETURNING id INTO v_alert_id;

  RETURN v_alert_id;
END;
$function$;
