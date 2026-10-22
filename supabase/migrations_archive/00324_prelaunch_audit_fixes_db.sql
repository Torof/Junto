-- Migration 00324: pre-launch audit fixes (DB layer)
--
-- Four fixes surfaced by the pre-launch audit (2026-07-13):
--   1. unregister_as_pro referenced the dropped `is_recurring` column (00248),
--      so Pro->Free downgrade always errored (42703). Remove the dead guard.
--   2. wall_messages_select's "hide suspended authors" clause was a silent no-op
--      (RLS recursion on users). Use the private.user_is_suspended() predicate,
--      exactly as the 00256 sweep did for activities/pro_profiles.
--   3. create_gpx_trace rejected > 5000 points while the GPX parser allows 10000
--      and the activity/share trace functions allow 10000 — align the cap.
--   4. moderate_report's inline suspend could hit a co-admin or self (the guards
--      exist on admin_suspend_user but were missing here); its admin check also
--      didn't exclude a suspended admin. Close both.

-- ---------------------------------------------------------------------------
-- 1. unregister_as_pro — drop the dead is_recurring guard
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION unregister_as_pro()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  DELETE FROM pro_profiles WHERE user_id = v_user_id;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET tier = 'free' WHERE id = v_user_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. wall_messages_select — real suspended-author hide via the predicate
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "wall_messages_select" ON wall_messages;
CREATE POLICY "wall_messages_select"
  ON wall_messages FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM participations
      WHERE activity_id = wall_messages.activity_id
      AND user_id = auth.uid()
      AND status = 'accepted'
    )
    AND (wall_messages.user_id IS NULL OR wall_messages.user_id NOT IN (
      SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid()
    ))
    AND (wall_messages.user_id IS NULL OR NOT private.user_is_suspended(wall_messages.user_id))
    AND deleted_at IS NULL
  );

-- ---------------------------------------------------------------------------
-- 3. create_gpx_trace — align the point cap to 10000 (parser + trace funcs)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_gpx_trace(
  p_name TEXT,
  p_geojson JSONB
)
RETURNS gpx_traces
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_name TEXT;
  v_geom geometry;
  v_distance_km NUMERIC(7,2);
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

  INSERT INTO gpx_traces (user_id, name, geojson, distance_km, created_at, updated_at)
  VALUES (v_user_id, v_name, p_geojson, v_distance_km, now(), now())
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. moderate_report — suspend-branch guards + suspended-admin exclusion
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION moderate_report(
  p_report_id UUID,
  p_action TEXT,
  p_admin_note TEXT DEFAULT NULL,
  p_suspend_user_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_report RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND is_admin = true AND suspended_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_action NOT IN ('dismissed', 'actioned') THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT id, status INTO v_report FROM reports WHERE id = p_report_id;
  IF v_report IS NULL OR v_report.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  UPDATE reports
  SET status = p_action, admin_note = p_admin_note, resolved_at = now()
  WHERE id = p_report_id;

  IF p_suspend_user_id IS NOT NULL AND p_action = 'actioned' THEN
    -- An admin can't suspend themselves or a co-admin (charter — admin status
    -- is managed at SQL level).
    IF p_suspend_user_id = v_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    IF EXISTS (SELECT 1 FROM users WHERE id = p_suspend_user_id AND is_admin = true) THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE users SET suspended_at = now() WHERE id = p_suspend_user_id AND suspended_at IS NULL;
  END IF;

  PERFORM log_admin_action(
    v_user_id, 'moderate_report', 'report', p_report_id, p_admin_note,
    jsonb_build_object('action', p_action, 'suspended_user_id', p_suspend_user_id)
  );
END;
$$;
