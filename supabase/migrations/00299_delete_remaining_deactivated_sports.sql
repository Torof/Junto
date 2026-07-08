-- ============================================================================
-- 00299 — Delete the remaining deactivated sports + their referencing records
--
-- The 8 that survived 00298 (badminton, crossfit, football, horseback-riding,
-- rock-fishing, skateboarding, tennis, volleyball) are only referenced by
-- pre-launch/test activities & offerings (Scott confirmed disposable). Delete
-- those records (children cascade — no RESTRICT FK to activities/offerings),
-- then the sports, then cascade-clean the freed keys.
-- ============================================================================

-- 1. Referencing records for inactive sports (cascade to participations,
--    wall messages, votes, etc.).
DELETE FROM pro_offerings WHERE sport_id IN (SELECT id FROM sports WHERE is_active = false);
DELETE FROM activities    WHERE sport_id IN (SELECT id FROM sports WHERE is_active = false);

-- 2. The sports themselves (now unreferenced).
DELETE FROM sports WHERE is_active = false;

-- 3. Cascade-clean freed keys.
UPDATE gear_catalog g
SET sport_keys = ARRAY(
      SELECT k FROM unnest(g.sport_keys) k
      WHERE EXISTS (SELECT 1 FROM sports s WHERE s.key = k)
    )
WHERE EXISTS (
  SELECT 1 FROM unnest(g.sport_keys) k
  WHERE NOT EXISTS (SELECT 1 FROM sports s WHERE s.key = k)
);

DELETE FROM activity_alerts al
WHERE al.sport_key IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM sports s WHERE s.key = al.sport_key);

SELECT set_config('junto.bypass_lock', 'true', true);

UPDATE users u
SET levels_per_sport = COALESCE((
      SELECT jsonb_object_agg(kv.key, kv.value)
      FROM jsonb_each(u.levels_per_sport) kv
      WHERE EXISTS (SELECT 1 FROM sports s WHERE s.key = kv.key)
    ), '{}'::jsonb)
WHERE u.levels_per_sport IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM jsonb_each(u.levels_per_sport) kv
    WHERE NOT EXISTS (SELECT 1 FROM sports s WHERE s.key = kv.key)
  );

UPDATE users u
SET sports = COALESCE((
      SELECT jsonb_agg(elem)
      FROM jsonb_array_elements_text(u.sports) elem
      WHERE EXISTS (SELECT 1 FROM sports s WHERE s.key = elem)
    ), '[]'::jsonb)
WHERE u.sports IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM jsonb_array_elements_text(u.sports) elem
    WHERE NOT EXISTS (SELECT 1 FROM sports s WHERE s.key = elem)
  );

SELECT set_config('junto.bypass_lock', 'false', true);
