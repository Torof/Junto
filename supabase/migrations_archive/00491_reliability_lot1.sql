-- ============================================================================
-- 00491 — Phase fiabilité, lot 1 (présence et votes).
-- PR-1  La sortie d'un organisateur suspendu n'est jamais finalisée, quel que
--       soit l'appelant ; transition_single_activity réservée à l'organisateur
--       et aux participants acceptés ; check_activity_transitions retirée aux
--       clients (la tâche planifiée l'appelle chaque minute).
-- BUG   Les expirations de demandes de place et de contact tournent désormais
--       dans la tâche planifiée (avant : seulement quand l'app s'ouvrait).
-- PR-2  Votes comptés aussi sur une sortie où tout le monde était validé.
-- BR-2  Votes comptés sur une sortie sans validation de présence (entre
--       participants acceptés, à fin + 24 h).
-- PR-7  Trophées : une absence ne compte pas comme sortie.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.close_presence_window_for(p_activity_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_activity RECORD;
  v_target RECORD;
  v_accepted_count INTEGER;
BEGIN
  SELECT id, status, starts_at, duration, requires_presence, creator_id, deleted_at
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  -- 00429 : ne JAMAIS finaliser (donc ne jamais poser d'absence ni de pénalité)
  -- sur une sortie retirée par la modération. Le balayage cron filtre déjà
  -- deleted_at (00107) ; le chemin lazy, non → un participant qui ouvrait une
  -- vieille notification déclenchait les absences que le cron refusait de poser.
  IF v_activity.deleted_at IS NOT NULL THEN RETURN; END IF;
  IF v_activity.status != 'completed' THEN RETURN; END IF;
  IF now() <= v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' THEN RETURN; END IF;
  -- 00491 (PR-1): never finalise the outing of a suspended organiser — its
  -- participants received no reminder and could get no QR. Whoever calls.
  IF EXISTS (SELECT 1 FROM users c WHERE c.id = v_activity.creator_id AND c.suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  -- 00491 (BR-2): an outing WITHOUT presence check also asks for votes
  -- (notify_rate_participants): count them at end + 24 h between accepted
  -- participants — there is no presence to require.
  IF v_activity.requires_presence IS NOT TRUE THEN
    UPDATE reputation_votes rv
    SET counted_at = now()
    WHERE rv.activity_id = p_activity_id
      AND rv.counted_at IS NULL
      AND rv.voter_id <> rv.voted_id
      AND EXISTS (SELECT 1 FROM participations pv
                  WHERE pv.activity_id = p_activity_id AND pv.user_id = rv.voter_id AND pv.status = 'accepted')
      AND EXISTS (SELECT 1 FROM participations pt
                  WHERE pt.activity_id = p_activity_id AND pt.user_id = rv.voted_id AND pt.status = 'accepted');
    RETURN;
  END IF;

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
$function$;

CREATE OR REPLACE FUNCTION public.close_due_presence_windows()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_activity_id UUID;
BEGIN
  FOR v_activity_id IN
    SELECT a.id
    FROM activities a
    WHERE a.status = 'completed'
      AND a.requires_presence = TRUE
      AND a.starts_at + a.duration + INTERVAL '24 hours' < now()
      AND a.deleted_at IS NULL
      -- 00432 : ne JAMAIS finaliser une sortie dont le créateur est suspendu.
      -- Les 4 boucles de notification l'excluent déjà (00427) — sans cette
      -- garde, l'asymétrie était la pire des deux : les participants ne
      -- recevaient plus AUCUN signal, n'avaient aucun QR possible
      -- (create_presence_token refuse), et prenaient quand même tous une
      -- absence + pénalité de fiabilité à fin+24h sans avoir rien pu faire.
      AND NOT EXISTS (
        SELECT 1 FROM users c
        WHERE c.id = a.creator_id AND c.suspended_at IS NOT NULL
      )
      AND EXISTS (
        SELECT 1 FROM participations p
        WHERE p.activity_id = a.id
          AND p.status = 'accepted'
          AND p.confirmed_present IS NULL
      )
  LOOP
    PERFORM close_presence_window_for(v_activity_id);
  END LOOP;

  -- 00491 (PR-2 / BR-2): votes left uncounted — an outing where everybody
  -- was already validated (the loop above skips it) or one without presence
  -- check. Bounded to outings ended in the last 14 days.
  FOR v_activity_id IN
    SELECT a.id
    FROM activities a
    WHERE a.status = 'completed'
      AND a.deleted_at IS NULL
      AND a.starts_at + a.duration + INTERVAL '24 hours' < now()
      AND a.starts_at + a.duration > now() - INTERVAL '14 days'
      AND NOT EXISTS (SELECT 1 FROM users c WHERE c.id = a.creator_id AND c.suspended_at IS NOT NULL)
      AND EXISTS (SELECT 1 FROM reputation_votes rv WHERE rv.activity_id = a.id AND rv.counted_at IS NULL)
  LOOP
    PERFORM close_presence_window_for(v_activity_id);
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.transition_single_activity(p_activity_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN NULL; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RETURN NULL;
  END IF;

  -- 00491 (PR-1): only the organiser or an accepted participant can push
  -- their outing forward (the minute sweep does it for everyone anyway).
  IF NOT EXISTS (SELECT 1 FROM activities a WHERE a.id = p_activity_id AND a.creator_id = v_user_id)
     AND NOT EXISTS (SELECT 1 FROM participations p
                     WHERE p.activity_id = p_activity_id AND p.user_id = v_user_id AND p.status = 'accepted') THEN
    RETURN NULL;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  SELECT id, creator_id, status, title, starts_at, duration, requires_presence, deleted_at
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN NULL; END IF;
  -- 00429 : même garde que le balayage cron — une sortie supprimée ne transite
  -- plus (sinon elle passait 'completed' puis se faisait finaliser).
  IF v_activity.deleted_at IS NOT NULL THEN RETURN v_activity.status; END IF;
  IF v_activity.status NOT IN ('published', 'in_progress', 'completed') THEN
    RETURN v_activity.status;
  END IF;

  IF v_activity.status = 'published'
     AND v_activity.starts_at + INTERVAL '2 hours' < now()
     AND (SELECT count(*) FROM participations p
          WHERE p.activity_id = p_activity_id
          AND p.status = 'accepted'
          AND p.user_id != v_activity.creator_id) = 0
  THEN
    UPDATE activities SET status = 'expired', updated_at = now()
    WHERE id = p_activity_id AND status = 'published';
    RETURN 'expired';
  END IF;

  IF v_activity.status = 'published' AND v_activity.starts_at <= now() THEN
    UPDATE activities SET status = 'in_progress', updated_at = now()
    WHERE id = p_activity_id AND status = 'published';
    IF FOUND THEN
      v_activity.status := 'in_progress';
      -- CORRIGÉ (00428) : notify_presence_reminders(UUID) a été SUPPRIMÉE en
      -- 00148 (spine de notifs simplifié) mais l'appel a été transporté
      -- verbatim de migration en migration (00136 → 00225 → 00286 → 00427).
      -- Résultat : cette RPC levait « function does not exist » à chaque
      -- appel, donc le flip completed, la fermeture de fenêtre de présence et
      -- rate_participants côté lazy n'ont JAMAIS tourné (les deux appelants
      -- client avalent l'erreur). Les rappels pré-event vivent dans
      -- notify_presence_pre_warning / _10min, appelés par le balayage cron.
      PERFORM notify_creator_qr_reminder(p_activity_id);
    END IF;
  ELSIF v_activity.status = 'in_progress' THEN
    PERFORM notify_creator_qr_reminder(p_activity_id);
  END IF;

  IF v_activity.status = 'in_progress' AND v_activity.starts_at + v_activity.duration <= now() THEN
    -- Solo end-of-window → expired, not completed (see header).
    IF (SELECT count(*) FROM participations p
        WHERE p.activity_id = p_activity_id
        AND p.status = 'accepted'
        AND p.user_id != v_activity.creator_id) = 0
    THEN
      UPDATE activities SET status = 'expired', updated_at = now()
      WHERE id = p_activity_id AND status = 'in_progress';
      IF FOUND THEN
        RETURN 'expired';
      END IF;
    END IF;

    UPDATE activities SET status = 'completed', updated_at = now()
    WHERE id = p_activity_id AND status = 'in_progress';
    IF FOUND THEN
      v_activity.status := 'completed';
    END IF;
  END IF;

  IF v_activity.status = 'completed' THEN
    PERFORM close_presence_window_for(p_activity_id);
    -- 00427: emit rate_participants here too (lazy path) — gates internally
    -- on the real vote window [end+15min, end+24h] + dedup.
    PERFORM notify_rate_participants(p_activity_id);
  END IF;

  RETURN v_activity.status;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_user_trophies(p_user_id uuid)
 RETURNS TABLE(category text, sport_key text, count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller UUID;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_caller AND suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  -- 00419 M3 : rideau démo.
  IF EXISTS (SELECT 1 FROM users du WHERE du.id = p_user_id AND du.is_demo = true)
     AND NOT demo_content_visible() THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT 'joined'::text, NULL::text,
    (SELECT count(*)::int
     FROM participations par
     JOIN activities a ON a.id = par.activity_id
     WHERE par.user_id = p_user_id
       AND par.status = 'accepted'
       AND par.confirmed_present IS DISTINCT FROM false  -- 00491 (PR-7): an absence is not an outing
       AND a.status = 'completed'
       AND a.creator_id != p_user_id
       AND a.deleted_at IS NULL)
  UNION ALL
  SELECT 'created'::text, NULL::text,
    (SELECT count(*)::int
     FROM activities
     WHERE creator_id = p_user_id
       AND status = 'completed'
       AND deleted_at IS NULL)
  UNION ALL
  SELECT 'sport'::text, s.key::text, count(*)::int
  FROM participations par
  JOIN activities a ON a.id = par.activity_id
  JOIN sports s ON s.id = a.sport_id
  WHERE par.user_id = p_user_id
    AND par.status = 'accepted'
    AND par.confirmed_present IS DISTINCT FROM false  -- 00491 (PR-7)
    AND a.status = 'completed'
    AND a.deleted_at IS NULL
  GROUP BY s.key
  HAVING count(*) > 0;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.check_activity_transitions() FROM PUBLIC, anon, authenticated;
SELECT cron.alter_job((SELECT jobid FROM cron.job WHERE jobname = 'junto-presence-sweep'),
                      command := 'SELECT public.check_activity_transitions();');
