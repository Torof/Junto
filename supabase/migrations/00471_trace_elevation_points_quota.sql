-- ============================================================================
-- 00471 — Audit octobre 2026, phase 3, L8 : le quota de trace-elevation
-- comptait des APPELS (150/h), chacun pouvant porter 10 000 points → 1,5 M
-- points/h par compte vers l'IGN (risque de bannissement des IP partagées de
-- Supabase). On garde le quota d'appels et on ajoute un quota de POINTS :
-- 50 000 points / heure glissante / compte (≈ 5 traces pleines, des centaines
-- de segments dessinés). Appelé par la fonction après le parse, avant l'IGN.
-- ============================================================================
ALTER TABLE trace_elevation_calls ADD COLUMN IF NOT EXISTS points INTEGER NOT NULL DEFAULT 0
  CHECK (points >= 0 AND points <= 10000);

CREATE OR REPLACE FUNCTION public.consume_trace_elevation_points(p_points integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user UUID;
  v_sum BIGINT;
BEGIN
  v_user := auth.uid();
  IF v_user IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF p_points IS NULL OR p_points < 1 OR p_points > 10000 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user::text || '_trace_elevation'));
  SELECT coalesce(sum(points), 0) INTO v_sum FROM trace_elevation_calls
  WHERE user_id = v_user AND called_at > now() - INTERVAL '1 hour';
  IF v_sum + p_points > 50000 THEN RAISE EXCEPTION 'junto.rate_limited'; END IF;
  INSERT INTO trace_elevation_calls (user_id, points) VALUES (v_user, p_points);
END;
$function$;
REVOKE ALL ON FUNCTION public.consume_trace_elevation_points(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.consume_trace_elevation_points(integer) TO authenticated;
