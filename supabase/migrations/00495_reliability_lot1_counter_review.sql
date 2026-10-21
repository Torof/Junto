-- ============================================================================
-- 00495 — Contre-vérification du lot fiabilité 1.
-- BR-2  Annulé : les votes d'une sortie SANS validation de présence ne sont
--       plus comptés (deux comptes pouvaient se fabriquer ou salir une
--       réputation avec une fausse sortie). Décision Scott en attente :
--       ne plus solliciter ces votes, ou les compter malgré le risque.
-- H2    Finalisation seulement entre fin + 24 h et fin + 48 h : un organisateur
--       suspendu puis réactivé ne fait plus tomber d'absences après coup.
-- M1    Tâche minute : chaque étape isolée (une erreur n'annule plus les autres).
-- PR-7  Niveaux par sport, badges de progression et trophées « créées » :
--       les absences et les sorties retirées ne comptent plus.
-- PR-10 Fiabilité : sorties retirées ou annulées ignorées.
-- L1    Sortie d'un organisateur suspendu figée aussi à l'ouverture (pas de
--       rappel, pas de demande de vote).
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

  -- 00495: outings WITHOUT presence check never count votes (00491's BR-2
  -- counting let two accounts farm or smear a reputation with a fake
  -- outing — pending Scott's decision on soliciting votes there at all).
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  -- 00495: finalise only in the normal window (end + 24 h … + 48 h). Later
  -- means the outing was frozen (organiser suspended, then reinstated):
  -- nobody gets an absence after the fact.
  IF now() > v_activity.starts_at + v_activity.duration + INTERVAL '48 hours' THEN RETURN; END IF;

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
      AND a.starts_at + a.duration + INTERVAL '48 hours' > now()  -- 00495
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
      AND a.starts_at + a.duration + INTERVAL '48 hours' > now()  -- 00495
      AND a.requires_presence = TRUE  -- 00495
      AND NOT EXISTS (SELECT 1 FROM users c WHERE c.id = a.creator_id AND c.suspended_at IS NOT NULL)
      AND EXISTS (SELECT 1 FROM reputation_votes rv WHERE rv.activity_id = a.id AND rv.counted_at IS NULL)
  LOOP
    PERFORM close_presence_window_for(v_activity_id);
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.check_activity_transitions()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext('activity_transitions')) THEN
    RETURN;
  END IF;

  -- 00495: each step isolated — a failure in one must not roll back the
  -- others (presence finalisation, notifications, expirations).
  BEGIN PERFORM transition_statuses_only();
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'transition_statuses_only: %', SQLERRM; END;
  BEGIN PERFORM expire_stale_contact_requests();
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'expire_stale_contact_requests: %', SQLERRM; END;
  BEGIN PERFORM expire_idle_seat_requests();
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'expire_idle_seat_requests: %', SQLERRM; END;
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

  PERFORM set_config('junto.bypass_lock', 'true', true);

  SELECT id, creator_id, status, title, starts_at, duration, requires_presence, deleted_at
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN NULL; END IF;
  -- 00495: a suspended organiser's outing is frozen (no reminders, no vote
  -- requests, no finalisation) — same as the minute sweep.
  IF private.user_is_suspended(v_activity.creator_id) THEN RETURN v_activity.status; END IF;
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

CREATE OR REPLACE FUNCTION public.get_user_sport_levels(p_user_id uuid)
 RETURNS TABLE(sport_key text, dots smallint, last_at timestamp with time zone, first_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH completed AS (
    SELECT s.key AS sport_key, a.level AS level, a.starts_at AS at
    FROM participations p
    JOIN activities a ON a.id = p.activity_id
    JOIN sports s ON s.id = a.sport_id
    WHERE p.user_id = p_user_id
      AND p.status = 'accepted'
      AND p.confirmed_present IS DISTINCT FROM false  -- 00495 (PR-7)
      AND a.status = 'completed'
      AND a.deleted_at IS NULL  -- 00495
      -- 00419 M3 : rideau démo.
      AND NOT (
        EXISTS (SELECT 1 FROM users du WHERE du.id = p_user_id AND du.is_demo = true)
        AND NOT demo_content_visible()
      )
  ),
  agg AS (
    SELECT
      completed.sport_key,
      count(*) AS total,
      count(*) FILTER (
        WHERE completed.level IN ('intermédiaire', 'intermediate', 'avancé', 'advanced', 'expert')
      ) AS at_intermediate,
      count(*) FILTER (
        WHERE completed.level IN ('avancé', 'advanced', 'expert')
      ) AS at_advanced,
      count(*) FILTER (WHERE completed.level = 'expert') AS at_expert,
      max(completed.at) AS last_at,
      min(completed.at) AS first_at
    FROM completed
    GROUP BY completed.sport_key
  )
  SELECT
    agg.sport_key,
    (CASE
      WHEN agg.at_expert >= 3 THEN 4
      WHEN agg.at_advanced >= 5 THEN 3
      WHEN agg.at_intermediate >= 3 THEN 2
      WHEN agg.total >= 1 THEN 1
      ELSE 0
    END)::SMALLINT AS dots,
    agg.last_at,
    agg.first_at
  FROM agg
  WHERE agg.total > 0;
$function$;

CREATE OR REPLACE FUNCTION public.award_badge_progression(p_user_id uuid, p_silent boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count INTEGER;
  v_tier TEXT;
  v_inserted UUID;
  v_label TEXT;
BEGIN
  -- Joined activities (where the user wasn't the creator)
  SELECT count(*) INTO v_count
  FROM participations par
  JOIN activities a ON a.id = par.activity_id
  WHERE par.user_id = p_user_id
    AND par.status = 'accepted'
    AND par.confirmed_present IS DISTINCT FROM false  -- 00495 (PR-7)
    AND a.status = 'completed'
    AND a.creator_id != p_user_id
    AND a.deleted_at IS NULL;
  v_tier := badge_tier_for(v_count);
  IF v_tier IS NOT NULL THEN
    INSERT INTO user_badge_progression (user_id, category, sport_key, tier_key)
    VALUES (p_user_id, 'joined', NULL, v_tier)
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_inserted;
    IF v_inserted IS NOT NULL AND NOT p_silent THEN
      v_label := badge_label_fr('joined', v_tier);
      PERFORM create_notification(
        p_user_id,
        'badge_unlocked',
        'Nouveau badge !',
        'Tu es maintenant ' || v_label,
        jsonb_build_object('category', 'joined', 'tier', v_tier, 'params', jsonb_build_object('label', v_label))
      );
    END IF;
  END IF;
  v_inserted := NULL;

  -- Created activities
  SELECT count(*) INTO v_count
  FROM activities
  WHERE creator_id = p_user_id
    AND status = 'completed'
    AND deleted_at IS NULL;
  v_tier := badge_tier_for(v_count);
  IF v_tier IS NOT NULL THEN
    INSERT INTO user_badge_progression (user_id, category, sport_key, tier_key)
    VALUES (p_user_id, 'created', NULL, v_tier)
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_inserted;
    IF v_inserted IS NOT NULL AND NOT p_silent THEN
      v_label := badge_label_fr('created', v_tier);
      PERFORM create_notification(
        p_user_id,
        'badge_unlocked',
        'Nouveau badge !',
        'Tu es maintenant ' || v_label,
        jsonb_build_object('category', 'created', 'tier', v_tier, 'params', jsonb_build_object('label', v_label))
      );
    END IF;
  END IF;
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
       AND deleted_at IS NULL
       -- 00495 (PR-7): not an outing its organiser was absent from.
       AND NOT EXISTS (SELECT 1 FROM participations cp
                       WHERE cp.activity_id = activities.id AND cp.user_id = p_user_id
                         AND cp.confirmed_present = false))
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

CREATE OR REPLACE FUNCTION public.recalculate_reliability_score(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  -- 00435 : constante bayésienne 3 → 1. Avec 3, les scores étaient écrasés
  -- vers le haut au point que le signal ne discriminait plus : quelqu'un qui
  -- s'inscrit à une seule sortie et n'y va pas affichait (3+0)/(3+1) = 75 %,
  -- soit « Bonne » — le MÊME palier qu'un habitué irréprochable — et il fallait
  -- quatre défections consécutives pour tomber en « Faible ».
  -- Avec 1 : 1 absence sur 1 → 50 % (« Correcte »), 2 sur 2 → 33 % (« Faible »),
  -- et un historique sain protège toujours (10 présences + 1 absence → 92 %,
  -- « Excellente »). Un nouveau compte reste à NULL (palier « nouveau ») jusqu'à
  -- sa première sortie terminée, donc on n'affiche jamais 100 % à quelqu'un qui
  -- n'a rien fait.
  v_prior CONSTANT INTEGER := 1;
  v_total INTEGER;
  v_present INTEGER;
  v_late_cancels INTEGER;
  v_score FLOAT;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('reliability_' || p_user_id::text));

  -- Validations on activities where the user is the creator AND no other
  -- accepted participant exists are recorded but don't count toward
  -- reliability — solo activities can't be peer-witnessed. The next recalc
  -- after a participant joins picks them up automatically.
  SELECT count(*) INTO v_total
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.user_id = p_user_id
    AND p.confirmed_present IS NOT NULL
    AND a.deleted_at IS NULL AND a.status <> 'cancelled'  -- 00495 (PR-10)
    AND NOT (
      p.user_id = a.creator_id
      AND NOT EXISTS (
        SELECT 1 FROM participations p2
        WHERE p2.activity_id = p.activity_id
          AND p2.user_id != p.user_id
          AND p2.status = 'accepted'
      )
    );

  SELECT count(*) INTO v_present
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.user_id = p_user_id
    AND p.confirmed_present = true
    AND a.deleted_at IS NULL AND a.status <> 'cancelled'  -- 00495 (PR-10)
    AND NOT (
      p.user_id = a.creator_id
      AND NOT EXISTS (
        SELECT 1 FROM participations p2
        WHERE p2.activity_id = p.activity_id
          AND p2.user_id != p.user_id
          AND p2.status = 'accepted'
      )
    );

  -- 00478 (PR-4): late cancels come from the late_cancels ledger. One per
  -- outing; not counted once the person has a presence verdict on that outing
  -- (no double count after a rejoin), nor on outings cancelled or removed.
  SELECT count(*) INTO v_late_cancels
  FROM late_cancels lc
  JOIN activities a ON a.id = lc.activity_id
  WHERE lc.user_id = p_user_id
    AND lc.waived = FALSE
    AND a.requires_presence = TRUE
    AND a.status <> 'cancelled'
    AND a.deleted_at IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM participations p
      WHERE p.activity_id = lc.activity_id AND p.user_id = lc.user_id
        AND p.confirmed_present IS NOT NULL
    );

  v_score := ROUND(
    (((v_prior + v_present)::float / (v_prior + v_total + v_late_cancels)::float) * 100)::numeric,
    1
  )::float;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET reliability_score = v_score WHERE id = p_user_id;
END;
$function$;
