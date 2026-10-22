-- ============================================================================
-- 00297 — Clean orphaned sport keys from user data
--
-- 00276 split/removed generic sport keys (climbing, mountain-biking) and
-- re-pointed activities/pro_offerings, but NOT users.levels_per_sport /
-- users.sports. Those orphaned keys linger in profiles and render via leftover
-- i18n labels ("Escalade"). Strip any key from a user's declared level map and
-- sports list that no longer exists in the sports reference table.
--
-- levels_per_sport is now privileged (00295) — the whitelist trigger forces it
-- to OLD on direct UPDATE, so we bypass it for this maintenance write.
-- ============================================================================
SELECT set_config('junto.bypass_lock', 'true', true);

-- levels_per_sport (jsonb object) — keep only keys present in sports
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

-- sports (jsonb array of keys) — keep only keys present in sports
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
