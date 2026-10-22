-- ============================================================================
-- 00454 — trace-elevation quota: 30 → 150 / rolling hour / user.
--
-- 00452 sized the quota for one IGN call per trace (at save). Scott 2026-10-16
-- wants the D+ live while DRAWING: the draw modal now enriches each new
-- segment as it is placed (debounced, un-enriched segments batched in one
-- call), so a drawing session costs about one call per tap. 150/h matches the
-- snap-trail budget (200/h) and still rules out a relay. Body = 00452 with the
-- constant changed; chain unchanged.
-- ============================================================================
CREATE OR REPLACE FUNCTION consume_trace_elevation_quota()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
  SELECT count(*) INTO v_count FROM trace_elevation_calls WHERE user_id = v_user;
  IF v_count >= 150 THEN RAISE EXCEPTION 'junto.rate_limited'; END IF;
  INSERT INTO trace_elevation_calls (user_id) VALUES (v_user);
END;
$$;
REVOKE ALL ON FUNCTION consume_trace_elevation_quota() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION consume_trace_elevation_quota() TO authenticated;
