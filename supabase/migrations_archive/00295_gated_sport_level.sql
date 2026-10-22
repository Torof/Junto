-- ============================================================================
-- 00295 — Gated self-declared sport level (set_sport_level)
--
-- Makes the per-sport level tamper-proof so the peer gate is real:
--   1. `levels_per_sport` becomes PRIVILEGED — moved from the writable whitelist
--      to the forced-to-OLD list in handle_user_update. Direct client updates
--      can no longer change it (they silently keep OLD).
--   2. New SECURITY DEFINER function `set_sport_level` is the ONLY way to write
--      a level. Rules (DECISIONS.md 2026-07-08): first declaration free (any
--      tier), one step at a time, UP requires peer net (right − over) ≥ 3 over a
--      12-month window (matching the display), DOWN free, votes reset on any
--      change, no removal.
--
-- NOTE: this locks the level column — the old batch editor's write becomes a
-- no-op. Ships together with the client rework (Gérer drawer + tooltip buttons)
-- that calls set_sport_level.
-- ============================================================================

-- 1) handle_user_update — reproduced from 00066 with levels_per_sport moved to
--    the forced-to-OLD (privileged) list.
CREATE OR REPLACE FUNCTION handle_user_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    NEW.updated_at := now();
    RETURN NEW;
  END IF;

  -- WHITELIST: any non-allowed column is forced back to its OLD value.
  -- Allowed (writable by the user): display_name, avatar_url, bio, sports, notification_preferences
  -- `levels_per_sport` is NO LONGER writable directly — only via set_sport_level
  -- (peer-gated). Forced to OLD below.
  NEW.id := OLD.id;
  NEW.email := OLD.email;
  NEW.created_at := OLD.created_at;
  NEW.date_of_birth := OLD.date_of_birth;
  NEW.phone_verified := OLD.phone_verified;
  NEW.phone_verified_at := OLD.phone_verified_at;
  NEW.tier := OLD.tier;
  NEW.is_pro_verified := OLD.is_pro_verified;
  NEW.pro_verified_at := OLD.pro_verified_at;
  NEW.is_admin := OLD.is_admin;
  NEW.suspended_at := OLD.suspended_at;
  NEW.accepted_tos_at := OLD.accepted_tos_at;
  NEW.accepted_privacy_at := OLD.accepted_privacy_at;
  NEW.tutorial_seen_at := OLD.tutorial_seen_at;
  NEW.push_token := OLD.push_token;
  NEW.reliability_score := OLD.reliability_score;
  NEW.levels_per_sport := OLD.levels_per_sport;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION handle_user_update FROM anon, authenticated, PUBLIC;

-- 2) set_sport_level — the only writer of levels_per_sport.
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

  -- target tier must be one of the 4 valid tiers
  v_ord_new := array_position(v_tiers, p_new_level);
  IF v_ord_new IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- sport must exist
  IF NOT EXISTS (SELECT 1 FROM sports WHERE key = p_sport_key) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- serialize a user's own level changes (guards the read-vote-then-write gate)
  PERFORM pg_advisory_xact_lock(hashtext('sport_level:' || v_user_id::text));

  SELECT levels_per_sport ->> p_sport_key INTO v_current FROM users WHERE id = v_user_id;

  IF v_current IS NOT NULL AND v_current <> '' THEN
    -- CHANGE of an existing declaration
    v_ord_cur := array_position(v_tiers, v_current);
    IF v_ord_cur IS NOT NULL THEN
      IF v_ord_new = v_ord_cur THEN RETURN; END IF;           -- no-op
      IF abs(v_ord_new - v_ord_cur) <> 1 THEN                 -- one step at a time
        RAISE EXCEPTION 'Operation not permitted';
      END IF;
      IF v_ord_new > v_ord_cur THEN
        -- going UP: require net (right − over) ≥ 3 for this sport (12-mo window)
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
      -- going DOWN: allowed, no check
    END IF;

    -- reset: any change refreshes the peer verdict for this sport
    DELETE FROM reputation_votes rv
    USING activities a, sports s
    WHERE rv.voted_id = v_user_id
      AND rv.activity_id = a.id
      AND a.sport_id = s.id
      AND s.key = p_sport_key
      AND rv.badge_key IN ('level_right', 'level_over');
  END IF;
  -- else: first declaration — free, no votes to reset

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users
  SET levels_per_sport = COALESCE(levels_per_sport, '{}'::jsonb)
                         || jsonb_build_object(p_sport_key, p_new_level),
      sports = CASE
                 WHEN p_sport_key = ANY(COALESCE(sports, ARRAY[]::text[])) THEN sports
                 ELSE array_append(COALESCE(sports, ARRAY[]::text[]), p_sport_key)
               END
  WHERE id = v_user_id;
  PERFORM set_config('junto.bypass_lock', 'false', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION set_sport_level(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION set_sport_level(TEXT, TEXT) TO authenticated;
