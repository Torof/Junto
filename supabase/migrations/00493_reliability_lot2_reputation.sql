-- ============================================================================
-- 00493 — Phase fiabilité, lot 2 (réputation).
-- PR-3  Les votants ne sont listés que pour un trait POSITIF donné par au
--       moins 5 personnes ; un vote négatif ne révèle jamais son auteur, ni par
--       la fonction ni en lecture directe (la personne visée ne lit plus les
--       lignes de vote qui la concernent ; chacun lit les siennes).
-- PR-11 Seuil des badges mis en avant : 5 personnes, pas 5 votes.
-- PR-12 Voter deux fois le même trait ne renvoie plus d'erreur brute.
-- IX-3  Rideau démo sur get_voters_for_badge, get_top_vouched_badges,
--       get_user_sport_level_votes.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_voters_for_badge(p_user_id uuid, p_badge_key text)
 RETURNS TABLE(voter_id uuid, display_name text, avatar_url text, voted_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  -- 00493 (IX-3): demo curtain, like get_user_reputation.
  IF EXISTS (SELECT 1 FROM users du WHERE du.id = p_user_id AND du.is_demo = true)
     AND NOT demo_content_visible() THEN
    RETURN;
  END IF;
  -- 00493 (PR-3): voters are shown only for a POSITIVE trait, and only once
  -- at least 5 different people gave it (the app shows the trait from 5 on).
  -- A negative vote never reveals its author (no retaliation).
  IF p_badge_key NOT IN ('punctual', 'prepared', 'conciliant', 'prudent') THEN RETURN; END IF;
  IF (SELECT count(DISTINCT rv.voter_id) FROM reputation_votes rv
      WHERE rv.voted_id = p_user_id AND rv.badge_key = p_badge_key AND rv.counted_at IS NOT NULL) < 5 THEN
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
$function$;

CREATE OR REPLACE FUNCTION public.get_top_vouched_badges(p_user_ids uuid[])
 RETURNS TABLE(user_id uuid, badge_key text, vote_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      COUNT(DISTINCT rv.voter_id)::INTEGER AS vote_count  -- 00493 (PR-11): people, not votes
    FROM reputation_votes rv
    WHERE rv.voted_id = ANY(p_user_ids)
      AND rv.badge_key IN ('punctual', 'prepared', 'conciliant', 'prudent')
      AND rv.counted_at IS NOT NULL
      -- 00493 (IX-3): demo curtain.
      AND (NOT EXISTS (SELECT 1 FROM users du WHERE du.id = rv.voted_id AND du.is_demo) OR demo_content_visible())
    GROUP BY rv.voted_id, rv.badge_key
    HAVING COUNT(DISTINCT rv.voter_id) >= 5
  )
  SELECT DISTINCT ON (counts.voted_id)
    counts.voted_id   AS user_id,
    counts.badge_key  AS badge_key,
    counts.vote_count AS vote_count
  FROM counts
  ORDER BY counts.voted_id, counts.vote_count DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_user_sport_level_votes(p_user_id uuid)
 RETURNS TABLE(sport_key text, level_over integer, level_right integer)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    -- 00493 (IX-3): demo curtain.
    AND (NOT EXISTS (SELECT 1 FROM users du WHERE du.id = p_user_id AND du.is_demo) OR demo_content_visible())
  GROUP BY s.key
  HAVING count(*) > 0;
$function$;

CREATE OR REPLACE FUNCTION public.give_reputation_badge(p_voted_id uuid, p_activity_id uuid, p_badge_key text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_recent_count INTEGER;
  v_valid_keys TEXT[] := ARRAY[
    'punctual', 'prepared', 'conciliant', 'prudent',
    'unprepared', 'aggressive', 'reckless',
    'level_over', 'level_right'
  ];
  v_level_keys TEXT[] := ARRAY['level_over', 'level_right'];
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_voted_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = p_voted_id)
       OR (blocker_id = p_voted_id AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('reputation_vote:' || v_user_id::text));

  SELECT count(*) INTO v_recent_count
  FROM reputation_votes
  WHERE voter_id = v_user_id
    AND created_at > NOW() - INTERVAL '24 hours';
  IF v_recent_count >= 20 THEN RAISE EXCEPTION 'junto.badge_rate_limit'; END IF;

  IF NOT (p_badge_key = ANY(v_valid_keys)) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, status, starts_at, duration, sport_id INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL OR v_activity.status != 'completed' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF now() < v_activity.starts_at + v_activity.duration + INTERVAL '15 minutes' THEN
    RAISE EXCEPTION 'junto.badge_window_not_open';
  END IF;

  IF v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' < now() THEN
    RAISE EXCEPTION 'junto.badge_window_closed';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = p_voted_id AND status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- A level vote judges the accuracy of a DECLARED level. With no declaration,
  -- there is no reference point — reject. The client hides the level section for
  -- such targets, so this path is a backstop (stale client / tamper): generic.
  IF p_badge_key = ANY(v_level_keys) THEN
    IF NOT EXISTS (
      SELECT 1
      FROM users u
      JOIN sports s ON s.id = v_activity.sport_id
      WHERE u.id = p_voted_id
        AND COALESCE(u.levels_per_sport ->> s.key, '') <> ''
    ) THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  IF p_badge_key = ANY(v_level_keys) THEN
    DELETE FROM reputation_votes
    WHERE voter_id = v_user_id
      AND voted_id = p_voted_id
      AND activity_id = p_activity_id
      AND badge_key = ANY(v_level_keys);
  END IF;

  -- 00493 (PR-12): voting twice for the same trait is a no-op, not a raw
  -- unique-violation error.
  INSERT INTO reputation_votes (voter_id, voted_id, activity_id, badge_key, created_at)
  VALUES (v_user_id, p_voted_id, p_activity_id, p_badge_key, now())
  ON CONFLICT DO NOTHING;
END;
$function$;

DROP POLICY IF EXISTS reputation_votes_select ON reputation_votes;
CREATE POLICY reputation_votes_select ON reputation_votes FOR SELECT TO authenticated
  USING (auth.uid() = voter_id);
