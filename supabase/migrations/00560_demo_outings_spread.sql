-- ============================================================================
-- 00560 — Vingt-deux sorties démo à venir partageaient leur point de
-- rendez-vous (neuf groupes de 2-3 au centre d'une même commune, coordonnées
-- estimées des seeds 00334/00446) : des clusters insécables sur la carte
-- (Scott 2026-10-27). Chaque doublon s'écarte de 180 à 420 m dans une
-- direction propre (angle et distance dérivés de l'id) : même commune, autre
-- parking. Le premier de chaque groupe ne bouge pas. Règle : jamais deux
-- objets démo au même point.
-- ============================================================================

DO $$
DECLARE
  r record;
  v_i int;
  v_angle double precision;
  v_dist double precision;
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);
  FOR r IN
    WITH pts AS (
      SELECT id,
             extensions.ST_X(location_meeting::extensions.geometry) AS lng,
             extensions.ST_Y(location_meeting::extensions.geometry) AS lat,
             row_number() OVER (PARTITION BY round(extensions.ST_X(location_meeting::extensions.geometry)::numeric, 4),
                                             round(extensions.ST_Y(location_meeting::extensions.geometry)::numeric, 4)
                                ORDER BY id) AS rn
      FROM public.activities
      WHERE is_demo AND deleted_at IS NULL AND status NOT IN ('cancelled', 'completed')
    )
    SELECT id, lng, lat, rn FROM pts WHERE rn > 1
  LOOP
    -- A stable pseudo-random direction and distance from the id.
    v_i := ('x' || substr(md5(r.id::text), 1, 6))::bit(24)::int;
    v_angle := (v_i % 360) * pi() / 180.0;
    v_dist := 180 + (v_i % 241);              -- 180 → 420 m
    UPDATE public.activities
    SET location_meeting = extensions.ST_SetSRID(extensions.ST_MakePoint(
          r.lng + (v_dist * cos(v_angle)) / (111320.0 * cos(radians(r.lat))),
          r.lat + (v_dist * sin(v_angle)) / 110540.0), 4326)::extensions.geography
    WHERE id = r.id;
  END LOOP;
  PERFORM set_config('junto.bypass_lock', 'false', true);
END $$;
