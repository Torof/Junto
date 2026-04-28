-- Migration 00151: peer reputation badges — decay for negatives + last_at meta.
--
-- Refonte du système de badges peer (commu) :
-- - Positifs : compteur total inchangé. Visible dès la 1re vote (bronze 1-9 /
--   silver 10-49 / gold 50+). Tier calculé client-side.
-- - Négatifs : compteur "actif" calculé avec décroissance (1 vote/mois après
--   le dernier vote ; reset à chaque nouveau vote). Visible à partir de
--   5 votes actifs.
-- - Ajout de last_at (max(created_at) des votes par badge) pour le popover.
--
-- Les badges Junto auto (joined / created / sport, t1-t5) ne sont pas
-- impactés — c'est uniquement la commu qui change.

-- ============================================================================
-- 1. get_active_negative_count — décroissance 1/mois depuis le dernier vote
-- ============================================================================
-- Walks votes ordered by created_at, applies decay between consecutive
-- votes (floor(elapsed_days / 30) drops, floor at 0), then applies decay
-- between the last vote and now. Returns the active count.
--
-- Examples (in days, threshold for visibility = 5 active):
--   day 0   vote A             → active = 1
--   day 15  vote B             → active = 2
--   day 30  no event           → active = 2 (15 days since last < 30)
--   day 45  no event           → active = 1 (30 days elapsed since day 15)
--   day 75  no event           → active = 0 (60 days elapsed since day 15)
--   day 76  vote C             → active = 1 (A and B already decayed)

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

-- ============================================================================
-- 2. get_user_reputation — drop old, replace with one returning vote_count + last_at
-- ============================================================================
-- The new shape adds last_at (TIMESTAMPTZ) for the popover "Dernière obtention".
-- For negatives, vote_count is the active count (post-decay). For positives,
-- it's the raw total. The client distinguishes via POSITIVE_BADGES /
-- NEGATIVE_BADGES lists and computes tier from the count.
--
-- Drop the old 1-arg signature explicitly so we don't end up with two
-- overloads after the signature change.
DROP FUNCTION IF EXISTS get_user_reputation(UUID);

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
  v_negative_keys TEXT[] := ARRAY[
    'level_overestimated', 'difficult_attitude', 'unreliable_field', 'aggressive'
  ];
BEGIN
  RETURN QUERY
  WITH grouped AS (
    SELECT
      rv.badge_key,
      count(*)::int AS total_count,
      max(rv.created_at) AS max_at
    FROM reputation_votes rv
    WHERE rv.voted_id = p_user_id
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
    -- Drop negatives whose active count has fully decayed to 0 — the badge
    -- has effectively disappeared and shouldn't surface in any view.
    NOT (
      g.badge_key = ANY(v_negative_keys)
      AND get_active_negative_count(p_user_id, g.badge_key) = 0
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION get_user_reputation FROM anon;
GRANT EXECUTE ON FUNCTION get_user_reputation TO authenticated;
