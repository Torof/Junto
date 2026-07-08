-- ============================================================================
-- 00298 — Delete deactivated sports for good + cascade-clean dead keys
--
-- Scott's call: remove the deactivated (is_active = false) sports permanently;
-- future sports are added one at a time, on demand. RESTRICT-safe — a sport is
-- only dropped if NO activity / pro_offering references it (the two ON DELETE
-- RESTRICT FKs); any referenced one survives. Freed keys are then stripped from
-- gear tags, now-inert alerts, and user declarations (privileged → bypass).
-- ============================================================================

-- 1. Drop inactive, unreferenced sports.
DELETE FROM sports s
WHERE s.is_active = false
  AND NOT EXISTS (SELECT 1 FROM activities a WHERE a.sport_id = s.id)
  AND NOT EXISTS (SELECT 1 FROM pro_offerings po WHERE po.sport_id = s.id);

-- 2. gear_catalog.sport_keys (text[]) — drop keys no longer in sports.
UPDATE gear_catalog g
SET sport_keys = ARRAY(
      SELECT k FROM unnest(g.sport_keys) k
      WHERE EXISTS (SELECT 1 FROM sports s WHERE s.key = k)
    )
WHERE EXISTS (
  SELECT 1 FROM unnest(g.sport_keys) k
  WHERE NOT EXISTS (SELECT 1 FROM sports s WHERE s.key = k)
);

-- 3. activity_alerts — a sport_key that no longer exists can never fire; drop it.
DELETE FROM activity_alerts al
WHERE al.sport_key IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM sports s WHERE s.key = al.sport_key);

-- 4. users.levels_per_sport / users.sports (privileged column → bypass lock).
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
