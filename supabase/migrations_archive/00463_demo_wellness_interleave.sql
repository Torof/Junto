-- ============================================================================
-- 00463 — Les 15 sorties de 00462 se retrouvaient groupées en fin de
-- calendrier (du 15 au 21 novembre) : leur created_at « slot + 40 min »
-- dépassait presque toutes les sorties existantes, et le re-datage ordonne par
-- created_at. On les ré-intercale une sortie sur trois parmi les 50 existantes
-- (rangs 1, 4, 7, …) puis on ré-applique le calendrier deux-par-jour.
-- ============================================================================
DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  WITH existing AS (
    SELECT id, created_at, row_number() OVER (ORDER BY created_at, id) AS rn
    FROM activities
    WHERE is_demo = true AND deleted_at IS NULL AND id::text LIKE 'a0000000-%'
      AND id::text < 'a0000000-0000-4000-a000-000000000033'
  ),
  fresh AS (
    SELECT id, row_number() OVER (ORDER BY id) AS k
    FROM activities
    WHERE id::text BETWEEN 'a0000000-0000-4000-a000-000000000033' AND 'a0000000-0000-4000-a000-000000000041'
  )
  UPDATE activities a
  SET created_at = e.created_at + INTERVAL '1 second'
  FROM fresh f JOIN existing e ON e.rn = 1 + 3 * (f.k - 1)
  WHERE a.id = f.id;

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
