-- ============================================================================
-- 00464 — 00463 n'a pas suffi : les 24 sorties de 00446 partagent le même
-- created_at, donc « + 1 seconde » retombait après tout le bloc. On réécrit
-- created_at des 65 sorties démo en une séquence propre d'une minute par rang,
-- avec le motif E E E N (trois existantes, une nouvelle), puis on ré-applique
-- le calendrier deux-par-jour.
-- ============================================================================
DO $$
DECLARE v_base TIMESTAMPTZ;
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  SELECT min(created_at) INTO v_base
  FROM activities WHERE is_demo = true AND deleted_at IS NULL AND id::text LIKE 'a0000000-%';

  WITH existing AS (
    SELECT id, row_number() OVER (ORDER BY created_at, id) AS rn
    FROM activities
    WHERE is_demo = true AND deleted_at IS NULL AND id::text LIKE 'a0000000-%'
      AND id::text < 'a0000000-0000-4000-a000-000000000033'
  ),
  fresh AS (
    SELECT id, row_number() OVER (ORDER BY id) AS k
    FROM activities
    WHERE id::text BETWEEN 'a0000000-0000-4000-a000-000000000033' AND 'a0000000-0000-4000-a000-000000000041'
  ),
  slots AS (
    SELECT id, rn + ((rn - 1) / 3) AS slot FROM existing
    UNION ALL
    SELECT id, 4 * k AS slot FROM fresh
  )
  UPDATE activities a
  SET created_at = v_base + make_interval(mins => s.slot::int)
  FROM slots s
  WHERE a.id = s.id;

  WITH ordered AS (
    SELECT id, row_number() OVER (ORDER BY created_at, id) AS rn
    FROM activities
    WHERE is_demo = true AND deleted_at IS NULL AND id::text NOT LIKE 'c0000000-%'
  ),
  target AS (
    SELECT a.id, a.starts_at AS old_start,
           date_trunc('day', now())
             + make_interval(
                 days  => (1 + ((o.rn - 1) / 2))::int,
                 hours => (ARRAY[9,14,8,16,10,17,11,15])[((o.rn - 1) % 8) + 1],
                 mins  => (ARRAY[0,30,15,0,45,30,0,30])[((o.rn - 1) % 8) + 1]
               ) AS new_start
    FROM activities a JOIN ordered o ON o.id = a.id
  ),
  shifted_transport AS (
    UPDATE participations p
    SET transport_departs_at = p.transport_departs_at + (t.new_start - t.old_start)
    FROM target t
    WHERE p.activity_id = t.id AND p.transport_departs_at IS NOT NULL
    RETURNING p.id
  ),
  shifted_pickups AS (
    UPDATE seat_requests s
    SET requested_pickup_at = s.requested_pickup_at + (t.new_start - t.old_start)
    FROM target t
    WHERE s.activity_id = t.id AND s.requested_pickup_at IS NOT NULL
    RETURNING s.id
  )
  UPDATE activities a
  SET starts_at = t.new_start, status = 'published'
  FROM target t
  WHERE a.id = t.id;
END $$;
