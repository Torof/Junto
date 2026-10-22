-- ============================================================================
-- 00296 — Fix set_sport_level: `sports` is JSONB, not text[]
--
-- 00295 treated users.sports as a Postgres array (array_append / = ANY), but it
-- is JSONB ('[]'::jsonb). Every declaration failed with a SQL type error →
-- generic client error. Fix: use jsonb operators (`?` membership, `||` append).
-- Only the sports write changes; authorization chain is identical.
-- ============================================================================
CREATE OR REPLACE FUNCTION set_sport_level(
  p_sport_key TEXT,
  p_new_level TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_current TEXT;
  v_ord_new INT;
  v_ord_cur INT;
  v_green INT;
  v_red INT;
  v_tiers TEXT[] := ARRAY['débutant', 'intermédiaire', 'avancé', 'expert'];
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_ord_new := array_position(v_tiers, p_new_level);
  IF v_ord_new IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (SELECT 1 FROM sports WHERE key = p_sport_key) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('sport_level:' || v_user_id::text));

  SELECT levels_per_sport ->> p_sport_key INTO v_current FROM users WHERE id = v_user_id;

  IF v_current IS NOT NULL AND v_current <> '' THEN
    v_ord_cur := array_position(v_tiers, v_current);
    IF v_ord_cur IS NOT NULL THEN
      IF v_ord_new = v_ord_cur THEN RETURN; END IF;
      IF abs(v_ord_new - v_ord_cur) <> 1 THEN
        RAISE EXCEPTION 'Operation not permitted';
      END IF;
      IF v_ord_new > v_ord_cur THEN
        SELECT
          count(*) FILTER (WHERE rv.badge_key = 'level_right'),
          count(*) FILTER (WHERE rv.badge_key = 'level_over')
        INTO v_green, v_red
        FROM reputation_votes rv
        JOIN activities a ON a.id = rv.activity_id
        JOIN sports s ON s.id = a.sport_id
        WHERE rv.voted_id = v_user_id
          AND s.key = p_sport_key
          AND rv.badge_key IN ('level_right', 'level_over')
          AND rv.created_at > now() - INTERVAL '12 months';

        IF coalesce(v_green, 0) - coalesce(v_red, 0) < 3 THEN
          RAISE EXCEPTION 'junto.level_up_locked';
        END IF;
      END IF;
    END IF;

    DELETE FROM reputation_votes rv
    USING activities a, sports s
    WHERE rv.voted_id = v_user_id
      AND rv.activity_id = a.id
      AND a.sport_id = s.id
      AND s.key = p_sport_key
      AND rv.badge_key IN ('level_right', 'level_over');
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users
  SET levels_per_sport = COALESCE(levels_per_sport, '{}'::jsonb)
                         || jsonb_build_object(p_sport_key, p_new_level),
      sports = CASE
                 WHEN COALESCE(sports, '[]'::jsonb) ? p_sport_key THEN sports
                 ELSE COALESCE(sports, '[]'::jsonb) || to_jsonb(p_sport_key)
               END
  WHERE id = v_user_id;
  PERFORM set_config('junto.bypass_lock', 'false', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION set_sport_level(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION set_sport_level(TEXT, TEXT) TO authenticated;
