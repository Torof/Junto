-- ============================================================================
-- 00398 — Keep the demo profile HISTORY completed (Scott 2026-09-05).
-- The 00393 completed-history activities (c0000000-…) got re-published +
-- re-dated to the future by admin_set_demo_mode. Its `status <> 'completed'`
-- guard is a TRAP: the first time a history row slips to 'published' it stays
-- in the re-date pool forever (it's no longer 'completed'). So the rich demo
-- profiles lost their completed outings → empty counts/trophies.
--   (1) restore c0000000-… → status='completed' + staggered PAST dates.
--   (2) harden admin_set_demo_mode: re-date the SHOWCASE only by EXCLUDING the
--       history UUID range (c0000000-%) — robust, can't be trapped.
-- ============================================================================

-- (1) Restore the history to completed + past (bypass_lock: status/starts_at are
--     frozen on activities that have accepted participants).
DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  WITH ordered AS (
    SELECT id, row_number() OVER (ORDER BY id) AS rn
    FROM activities WHERE id::text LIKE 'c0000000-%' AND is_demo = true
  )
  UPDATE activities a
  SET status = 'completed',
      starts_at = date_trunc('day', now()) - make_interval(days => (o.rn * 5)::int) + INTERVAL '9 hours'
  FROM ordered o
  WHERE a.id = o.id;
  PERFORM set_config('junto.bypass_lock', 'false', true);
END $$;

-- (2) Harden the refresh: exclude the history range instead of relying on status.
CREATE OR REPLACE FUNCTION admin_set_demo_mode(p_on boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_admin uuid;
  v_base GEOGRAPHY;
  v_ws TIMESTAMPTZ;
  v_we TIMESTAMPTZ;
  v_sports TEXT[];
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM users WHERE id = v_admin AND is_admin = true AND suspended_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE app_config SET value = CASE WHEN p_on THEN 'true' ELSE 'false' END
  WHERE name = 'demo_mode';

  IF p_on THEN
    PERFORM set_config('junto.bypass_lock', 'true', true);

    -- Showcase demo activities only → future dates. The completed HISTORY
    -- (c0000000-…, feeds the rich profiles) is excluded by UUID range so it can
    -- never be dragged into the re-date pool (a status-only guard traps it).
    WITH ordered AS (
      SELECT id, row_number() OVER (ORDER BY created_at, id) AS rn
      FROM activities
      WHERE is_demo = true AND deleted_at IS NULL AND id::text NOT LIKE 'c0000000-%'
    )
    UPDATE activities a
    SET starts_at = date_trunc('day', now())
          + make_interval(
              days  => (1 + o.rn * 2)::int,
              hours => (ARRAY[9,14,11,17,8,16,10,15])[((o.rn - 1) % 8) + 1],
              mins  => (ARRAY[0,30,0,30,15,0,45,30])[((o.rn - 1) % 8) + 1]
            ),
        status = 'published'
    FROM ordered o
    WHERE a.id = o.id;

    -- Demo dispos mirror the enabling admin's own active dispo (see 00391).
    SELECT d.base, d.window_start, d.window_end, d.sport_keys
      INTO v_base, v_ws, v_we, v_sports
    FROM discovery_availabilities d
    WHERE d.user_id = v_admin AND d.is_active AND d.is_demo = false;

    IF v_base IS NOT NULL THEN
      WITH ordered AS (
        SELECT id, row_number() OVER (ORDER BY user_id) AS rn
        FROM discovery_availabilities WHERE is_demo = true
      )
      UPDATE discovery_availabilities dd
      SET sport_keys   = v_sports,
          window_start = v_ws,
          window_end   = v_we,
          radius_km    = (ARRAY[30,50,30])[((o.rn - 1) % 3) + 1],
          base = ST_SetSRID(ST_MakePoint(
                   ST_X(v_base::geometry) + (ARRAY[0.06,0.13,0.18])[((o.rn - 1) % 3) + 1],
                   ST_Y(v_base::geometry)), 4326)::geography,
          is_active = true
      FROM ordered o
      WHERE dd.id = o.id;
    END IF;
  END IF;

  PERFORM log_admin_action(
    v_admin,
    CASE WHEN p_on THEN 'demo_mode_on' ELSE 'demo_mode_off' END,
    'app_config', NULL, NULL, NULL
  );
END;
$$;
REVOKE ALL ON FUNCTION admin_set_demo_mode(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_set_demo_mode(boolean) TO authenticated;
