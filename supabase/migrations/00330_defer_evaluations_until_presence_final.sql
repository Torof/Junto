-- ============================================================================
-- 00330 — Defer co-participant evaluations until presence is finalised (Scott 2026-07-14)
--
-- Problem: give_reputation_badge (traits + sport level) had NO presence anchor.
-- Two accepted participants of a `completed` activity could judge each other's
-- level / stick negative traits even when the activity never required presence,
-- or when presence was required but nobody was ever confirmed present — a
-- baseless judgment and a fraud surface (two accounts that never met boosting /
-- smearing each other, unlocking level-ups).
--
-- Model (solution A): votes are DEPOSITED live during the T+15min..T+24h window
-- with no presence gate (vote freely, any order — no deadlock), but they are
-- PROVISIONAL. At the existing T+24h finaliser we resolve presence, then COMMIT
-- only the votes whose BOTH parties ended up `confirmed_present = true`. Presence
-- itself is untouched (stays live: QR/geo instant, peer testimony live).
--
-- Mechanism: reputation_votes.counted_at (NULL = provisional, not counted).
--   * give_reputation_badge unchanged — new column defaults NULL.
--   * close_presence_window_for sets counted_at for anchored votes at T+24h.
--   * every reader that surfaces RECEIVED reputation (the effect) counts only
--     counted_at IS NOT NULL. The peer-review screen's "my own votes" read
--     (get_activity_peer_review_state) is intentionally NOT filtered — a voter
--     must still see their provisional selections live.
--
-- reputation_votes has no client writes and no trigger; counted_at is server-
-- only. All functions below are reproduced verbatim from their latest version
-- with the single filter added (source migration noted per function).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Column + backfill
-- ----------------------------------------------------------------------------
ALTER TABLE reputation_votes ADD COLUMN IF NOT EXISTS counted_at TIMESTAMPTZ;

-- Purge any self-vote parasites (voter = voted). These are categorically
-- invalid — forbidden by CHECK (voter_id != voted_id) AND by give_reputation_badge's
-- self-vote block — and only exist as directly-seeded test garbage. Removing them
-- also unblocks the backfill UPDATE below, which would otherwise re-validate the
-- CHECK on such a row and fail.
DELETE FROM reputation_votes WHERE voter_id = voted_id;

-- Grandfather every existing (valid) vote as counted so nothing disappears on
-- deploy. (Moot after the pre-launch test-data purge, but correct regardless.)
UPDATE reputation_votes SET counted_at = created_at
WHERE counted_at IS NULL AND voter_id <> voted_id;

-- Speeds the received-effect reads, which all filter counted_at IS NOT NULL.
CREATE INDEX IF NOT EXISTS idx_reputation_votes_counted
  ON reputation_votes(voted_id)
  WHERE counted_at IS NOT NULL;

-- ----------------------------------------------------------------------------
-- 2) close_presence_window_for — reproduced from 00328 + the evaluation commit
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.close_presence_window_for(p_activity_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
  v_accepted_count INTEGER;
BEGIN
  SELECT id, status, starts_at, duration, requires_presence, creator_id
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.status != 'completed' THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF now() <= v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' THEN RETURN; END IF;

  -- Deferred evaluations: commit (make count) every reputation vote whose BOTH
  -- parties ended up confirmed present. Runs before the presence branching
  -- below — the confirmed-present set is already fixed (finalisation only flips
  -- NULLs to FALSE / neutralises, never adds a TRUE). requires_presence = false
  -- returned earlier, so a no-presence activity never commits any vote, and if
  -- nobody was confirmed present there is simply no anchored pair to commit.
  UPDATE reputation_votes rv
  SET counted_at = now()
  WHERE rv.activity_id = p_activity_id
    AND rv.counted_at IS NULL
    AND rv.voter_id <> rv.voted_id  -- defensive: a self-vote would break the CHECK re-validation
    AND EXISTS (
      SELECT 1 FROM participations pv
      WHERE pv.activity_id = p_activity_id
        AND pv.user_id = rv.voter_id
        AND pv.status = 'accepted'
        AND pv.confirmed_present = TRUE
    )
    AND EXISTS (
      SELECT 1 FROM participations pt
      WHERE pt.activity_id = p_activity_id
        AND pt.user_id = rv.voted_id
        AND pt.status = 'accepted'
        AND pt.confirmed_present = TRUE
    );

  SELECT count(*) INTO v_accepted_count
  FROM participations
  WHERE activity_id = p_activity_id AND status = 'accepted';

  -- Solo (creator alone): "absent" is undefined. Leave NULL untouched.
  IF v_accepted_count < 2 THEN RETURN; END IF;

  -- Rule C — exactly 2: presence only via QR/geo (peer testimony is circular).
  -- A non-creator confirmation auto-validates both (rule A), so its ABSENCE
  -- means the meetup wasn't verifiable -> re-expire, wipe any lone self-
  -- validation so nothing counts, and never penalise.
  IF v_accepted_count = 2 THEN
    IF NOT EXISTS (
      SELECT 1 FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted'
        AND user_id != v_activity.creator_id AND confirmed_present = TRUE
    ) THEN
      PERFORM set_config('junto.bypass_lock', 'true', true);
      UPDATE activities SET status = 'expired', updated_at = now()
      WHERE id = p_activity_id AND status = 'completed';
      FOR v_target IN
        SELECT user_id FROM participations
        WHERE activity_id = p_activity_id AND status = 'accepted'
          AND confirmed_present IS NOT NULL
      LOOP
        UPDATE participations SET confirmed_present = NULL
        WHERE activity_id = p_activity_id AND user_id = v_target.user_id AND status = 'accepted';
        PERFORM recalculate_reliability_score(v_target.user_id);
      END LOOP;
    END IF;
    RETURN;
  END IF;

  -- 3+ : the review happened iff at least one participant is confirmed present.
  PERFORM set_config('junto.bypass_lock', 'true', true);

  -- Nobody confirmed -> the review never ran. Can't tell absent from forgotten:
  -- stay neutral for everyone (expire, no penalty), like the 2-person case.
  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND status = 'accepted' AND confirmed_present = TRUE
  ) THEN
    UPDATE activities SET status = 'expired', updated_at = now()
    WHERE id = p_activity_id AND status = 'completed';
    RETURN;
  END IF;

  -- At least one presence established -> the unconfirmed are genuine no-shows.
  FOR v_target IN
    SELECT user_id FROM participations
    WHERE activity_id = p_activity_id
      AND status = 'accepted'
      AND confirmed_present IS NULL
  LOOP
    UPDATE participations
    SET confirmed_present = FALSE
    WHERE activity_id = p_activity_id
      AND user_id = v_target.user_id
      AND status = 'accepted'
      AND confirmed_present IS NULL;

    PERFORM recalculate_reliability_score(v_target.user_id);
  END LOOP;
END;
$$;

-- ----------------------------------------------------------------------------
-- 3) Effect readers — count only committed (counted_at IS NOT NULL) votes
-- ----------------------------------------------------------------------------

-- 3a) set_sport_level — reproduced from 00296, level-up gate filtered.
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
          AND rv.counted_at IS NOT NULL
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

-- 3b) get_user_reputation — reproduced from 00236, trait counts filtered.
CREATE OR REPLACE FUNCTION get_user_reputation(
  p_user_id UUID
)
RETURNS TABLE (
  badge_key TEXT,
  vote_count INTEGER,
  last_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller UUID;
  v_negative_keys TEXT[] := ARRAY[
    'unprepared', 'aggressive', 'reckless',
    'late_canceller', 'level_overestimated', 'unreliable_field', 'difficult_attitude'
  ];
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_caller AND suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH grouped AS (
    SELECT
      rv.badge_key,
      count(*)::int AS total_count,
      max(rv.created_at) AS max_at
    FROM reputation_votes rv
    WHERE rv.voted_id = p_user_id
      AND rv.counted_at IS NOT NULL
      AND rv.badge_key NOT IN ('level_over', 'level_right', 'level_under')
    GROUP BY rv.badge_key
  )
  SELECT
    g.badge_key,
    CASE
      WHEN g.badge_key = ANY(v_negative_keys)
        THEN get_active_negative_count(p_user_id, g.badge_key)
      ELSE g.total_count
    END AS vote_count,
    g.max_at AS last_at
  FROM grouped g
  WHERE
    NOT (
      g.badge_key = ANY(v_negative_keys)
      AND get_active_negative_count(p_user_id, g.badge_key) = 0
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION get_user_reputation FROM anon;
GRANT EXECUTE ON FUNCTION get_user_reputation TO authenticated;

-- 3c) get_active_negative_count — reproduced from 00151, decay source filtered.
CREATE OR REPLACE FUNCTION get_active_negative_count(
  p_voted_id UUID,
  p_badge_key TEXT
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_active INTEGER := 0;
  v_last_at TIMESTAMPTZ;
  v_vote RECORD;
  v_months_elapsed INTEGER;
BEGIN
  FOR v_vote IN
    SELECT created_at FROM reputation_votes
    WHERE voted_id = p_voted_id AND badge_key = p_badge_key
      AND counted_at IS NOT NULL
    ORDER BY created_at ASC
  LOOP
    IF v_last_at IS NOT NULL THEN
      v_months_elapsed := FLOOR(
        EXTRACT(EPOCH FROM (v_vote.created_at - v_last_at)) / (30.0 * 24 * 3600)
      )::INTEGER;
      v_active := GREATEST(0, v_active - v_months_elapsed);
    END IF;
    v_active := v_active + 1;
    v_last_at := v_vote.created_at;
  END LOOP;

  IF v_last_at IS NOT NULL THEN
    v_months_elapsed := FLOOR(
      EXTRACT(EPOCH FROM (NOW() - v_last_at)) / (30.0 * 24 * 3600)
    )::INTEGER;
    v_active := GREATEST(0, v_active - v_months_elapsed);
  END IF;

  RETURN v_active;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_active_negative_count FROM anon, authenticated;

-- 3d) get_voters_for_badge — reproduced from 00226, voter list filtered.
CREATE OR REPLACE FUNCTION get_voters_for_badge(
  p_user_id UUID,
  p_badge_key TEXT
)
RETURNS TABLE (
  voter_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  voted_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT *
  FROM (
    SELECT DISTINCT ON (rv.voter_id)
      pp.id           AS voter_id,
      pp.display_name AS display_name,
      pp.avatar_url   AS avatar_url,
      rv.created_at   AS voted_at
    FROM reputation_votes rv
    JOIN public_profiles pp ON pp.id = rv.voter_id
    WHERE rv.voted_id  = p_user_id
      AND rv.badge_key = p_badge_key
      AND rv.counted_at IS NOT NULL
    ORDER BY rv.voter_id, rv.created_at DESC
  ) deduped
  ORDER BY deduped.voted_at DESC;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_voters_for_badge FROM anon;
GRANT EXECUTE ON FUNCTION get_voters_for_badge TO authenticated;

-- 3e) get_top_vouched_badges — reproduced from 00226, tally filtered.
CREATE OR REPLACE FUNCTION get_top_vouched_badges(p_user_ids UUID[])
RETURNS TABLE (
  user_id UUID,
  badge_key TEXT,
  vote_count INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH counts AS (
    SELECT
      rv.voted_id,
      rv.badge_key,
      COUNT(*)::INTEGER AS vote_count
    FROM reputation_votes rv
    WHERE rv.voted_id = ANY(p_user_ids)
      AND rv.badge_key IN ('punctual', 'prepared', 'conciliant', 'prudent')
      AND rv.counted_at IS NOT NULL
    GROUP BY rv.voted_id, rv.badge_key
    HAVING COUNT(*) >= 5
  )
  SELECT DISTINCT ON (counts.voted_id)
    counts.voted_id   AS user_id,
    counts.badge_key  AS badge_key,
    counts.vote_count AS vote_count
  FROM counts
  ORDER BY counts.voted_id, counts.vote_count DESC;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_top_vouched_badges FROM anon;
GRANT EXECUTE ON FUNCTION get_top_vouched_badges TO authenticated;

-- 3f) get_user_sport_level_votes — reproduced from 00300, profile verdict filtered.
CREATE OR REPLACE FUNCTION get_user_sport_level_votes(p_user_id UUID)
RETURNS TABLE (
  sport_key TEXT,
  level_over INTEGER,
  level_right INTEGER
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    s.key AS sport_key,
    count(*) FILTER (WHERE rv.badge_key = 'level_over')::int AS level_over,
    count(*) FILTER (WHERE rv.badge_key = 'level_right')::int AS level_right
  FROM reputation_votes rv
  JOIN activities a ON a.id = rv.activity_id
  JOIN sports s ON s.id = a.sport_id
  WHERE rv.voted_id = p_user_id
    AND rv.badge_key IN ('level_over', 'level_right')
    AND rv.counted_at IS NOT NULL
    AND rv.created_at >= now() - INTERVAL '12 months'   -- sliding freshness window
  GROUP BY s.key
  HAVING count(*) > 0;
$$;

REVOKE EXECUTE ON FUNCTION get_user_sport_level_votes FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION get_user_sport_level_votes TO authenticated;
