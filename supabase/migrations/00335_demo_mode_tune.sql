-- ============================================================================
-- 00335 — Demo mode tuning: varied dates+times + exact pin coordinates
--
-- Scott's on-device review of Phase 2:
--   1. All demo activities landed at the same time (09:00) — the refresh only
--      varied the day, not the hour. Give each a distinct day AND time-of-day.
--   2. Exact coordinates for the objectives/offerings that were off (Scott read
--      them off the map). Rocher Baron + Combes were already exact and stay.
-- ============================================================================

-- 1) Refresh formula: distinct day + distinct hour/minute per demo activity.
--    (Reproduced from 00333 admin_set_demo_mode; only the starts_at expression
--    changes. Arrays cycle every 8 so it scales past 4 demo activities.)
CREATE OR REPLACE FUNCTION admin_set_demo_mode(p_on boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin uuid;
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
    WITH ordered AS (
      SELECT id, row_number() OVER (ORDER BY created_at, id) AS rn
      FROM activities WHERE is_demo = true AND deleted_at IS NULL
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

-- 2) Apply the new schedule + exact coordinates now (bypass_lock: activities
--    with accepted participants lock starts_at/location_objective otherwise).
DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  -- Immediate varied schedule (mirrors the function, so no re-toggle needed).
  WITH ordered AS (
    SELECT id, row_number() OVER (ORDER BY created_at, id) AS rn
    FROM activities WHERE is_demo = true AND deleted_at IS NULL
  )
  UPDATE activities a
  SET starts_at = date_trunc('day', now())
        + make_interval(
            days  => (1 + o.rn * 2)::int,
            hours => (ARRAY[9,14,11,17,8,16,10,15])[((o.rn - 1) % 8) + 1],
            mins  => (ARRAY[0,30,0,30,15,0,45,30])[((o.rn - 1) % 8) + 1]
          )
  FROM ordered o
  WHERE a.id = o.id;

  -- Exact objective coordinates.
  UPDATE activities
    SET location_objective = ST_SetSRID(ST_MakePoint(6.5610621, 44.8836709), 4326)::geography
    WHERE id = 'a0000000-0000-4000-a000-000000000001'; -- Croix d'Aquila
  UPDATE activities
    SET location_objective = ST_SetSRID(ST_MakePoint(6.583799, 44.878944), 4326)::geography
    WHERE id = 'a0000000-0000-4000-a000-000000000003'; -- Falaise de Puy-Chalvin

  -- Exact offering coordinates (Prorel: point is the takeoff "croix de la Nord").
  UPDATE pro_offerings
    SET location = ST_SetSRID(ST_MakePoint(6.527103, 44.788322), 4326)::geography
    WHERE id = 'b0000000-0000-4000-a000-000000000001'; -- Canyon du Fournel
  UPDATE pro_offerings
    SET location = ST_SetSRID(ST_MakePoint(6.669491, 45.00036), 4326)::geography
    WHERE id = 'b0000000-0000-4000-a000-000000000002'; -- Torrent des Acles
  UPDATE pro_offerings
    SET location = ST_SetSRID(ST_MakePoint(6.587573, 44.902003), 4326)::geography,
        location_name = 'Décollage du Prorel'
    WHERE id = 'b0000000-0000-4000-a000-000000000003'; -- Prorel (croix de la Nord)
END $$;
