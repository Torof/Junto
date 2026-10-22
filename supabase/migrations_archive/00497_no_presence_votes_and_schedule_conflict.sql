-- ============================================================================
-- 00497 — Décisions Scott (2026-10-21).
-- 1. Plus de votes sur une sortie sans validation de présence : ni demande de
--    vote, ni vote possible (junto.votes_need_presence). À revoir avec le temps.
-- 2. Pas deux sorties en même temps : une participation ne devient
--    « acceptée » que si la personne n'est pas déjà acceptée (ou organisatrice)
--    sur une sortie à venir ou en cours dont le créneau chevauche. Contrôle
--    au niveau des données : rejoindre, invitation, acceptation par
--    l'organisateur, création. Hors sorties démo.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.notify_rate_participants(p_activity_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_activity RECORD;
  v_target RECORD;
BEGIN
  SELECT id, title, status, starts_at, duration, deleted_at, requires_presence
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.deleted_at IS NOT NULL THEN RETURN; END IF;
  IF v_activity.status != 'completed' THEN RETURN; END IF;
  -- 00497 (Scott): no vote request on an outing without presence check.
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  -- La fenêtre de vote réelle : fin+15 min → fin+24 h. Avant : silence
  -- (le prochain balayage émettra) ; après : plus de sens, on n'émet jamais.
  IF now() < v_activity.starts_at + v_activity.duration + INTERVAL '15 minutes' THEN RETURN; END IF;
  IF now() > v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' THEN RETURN; END IF;

  -- Gate solo (00265) : personne à évaluer en dessous de 2 acceptés.
  IF (SELECT count(*) FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted') < 2 THEN
    RETURN;
  END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'rate_participants'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'rate_participants',
        'Évalue tes co-participants',
        '« ' || v_activity.title || ' » — dis-nous comment ça s''est passé.',
        jsonb_build_object('activity_id', p_activity_id, 'params', jsonb_build_object('title', v_activity.title))
      );
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
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

  SELECT id, status, starts_at, duration, sport_id, requires_presence INTO v_activity
  FROM activities WHERE id = p_activity_id
    AND deleted_at IS NULL;  -- 00496 (BR-8): no votes on a moderated outing

  IF v_activity IS NULL OR v_activity.status != 'completed' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00497 (Scott): votes only where presence was verified — an outing without
  -- it proves nobody was there, so it cannot build or smear a reputation.
  IF v_activity.requires_presence IS NOT TRUE THEN
    RAISE EXCEPTION 'junto.votes_need_presence';
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

CREATE OR REPLACE FUNCTION private.check_schedule_conflict()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_range TSTZRANGE;
BEGIN
  IF NEW.status <> 'accepted' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = 'accepted' THEN RETURN NEW; END IF;

  SELECT tstzrange(a.starts_at, a.starts_at + a.duration) INTO v_range
  FROM activities a
  WHERE a.id = NEW.activity_id AND NOT a.is_demo AND a.deleted_at IS NULL;
  IF v_range IS NULL THEN RETURN NEW; END IF;

  -- Serialise this person's acceptances (two joins at once).
  PERFORM pg_advisory_xact_lock(hashtext('schedule:' || NEW.user_id::text));

  IF EXISTS (
    SELECT 1 FROM participations p
    JOIN activities a ON a.id = p.activity_id
    WHERE p.user_id = NEW.user_id
      AND p.status = 'accepted'
      AND p.activity_id <> NEW.activity_id
      AND a.status IN ('published', 'in_progress')
      AND a.deleted_at IS NULL
      AND NOT a.is_demo
      AND tstzrange(a.starts_at, a.starts_at + a.duration) && v_range
  ) THEN
    IF auth.uid() IS NOT DISTINCT FROM NEW.user_id THEN
      RAISE EXCEPTION 'junto.schedule_conflict';
    ELSE
      RAISE EXCEPTION 'junto.participant_schedule_conflict';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION private.check_schedule_conflict() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_participations_schedule_conflict ON participations;
CREATE TRIGGER trg_participations_schedule_conflict
  BEFORE INSERT OR UPDATE OF status ON participations
  FOR EACH ROW EXECUTE FUNCTION private.check_schedule_conflict();
