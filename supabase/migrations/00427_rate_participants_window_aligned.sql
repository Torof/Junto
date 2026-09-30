-- ============================================================================
-- 00427 — « Évalue tes co-participants » n'arrive plus AVANT l'ouverture de la
-- fenêtre de vote (Scott 2026-09-30, refonte des refus muets du peer review).
--
-- Problème : le trigger de complétion (00265) émettait rate_participants à
-- l'instant du flip 'completed', mais la fenêtre de vote n'ouvre qu'à
-- fin+15 min (peer_validate_presence / give_reputation_badge) — taper la
-- notification dès réception garantissait un refus « trop tôt ».
--
-- Fix : l'émission quitte le trigger et passe dans les balayages (même famille
-- que peer_review_closing T+22h) via notify_rate_participants(), qui gate en
-- interne sur la VRAIE fenêtre [fin+15 min, fin+24 h] + dédup par
-- (user, activité). Émise par le sweep cron (transition_statuses_only) ET par
-- le chemin lazy (transition_single_activity, foreground). Le gate solo de
-- 00265 (≥2 participants acceptés) est conservé.
--
-- Bases vivantes vérifiées : on_activity_completed_award_badges=00265,
-- transition_statuses_only=00286, transition_single_activity=00286 (corps
-- repris verbatim, seuls les ajouts 00427 diffèrent). Signatures inchangées.
-- ============================================================================

-- ---------- 1. notify_rate_participants — interne, gates + dédup ----------
CREATE OR REPLACE FUNCTION notify_rate_participants(
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
BEGIN
  SELECT id, title, status, starts_at, duration, deleted_at
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.deleted_at IS NOT NULL THEN RETURN; END IF;
  IF v_activity.status != 'completed' THEN RETURN; END IF;
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
        'Comment s''est passé ' || v_activity.title || ' ?',
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION notify_rate_participants(UUID) FROM PUBLIC, anon, authenticated;

-- ---------- 2. Trigger de complétion (base 00265) : l'émission de
-- rate_participants en sort — la progression de badges y reste. ----------
CREATE OR REPLACE FUNCTION on_activity_completed_award_badges()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_participant RECORD;
BEGIN
  IF NEW.status = 'completed' AND (OLD.status IS DISTINCT FROM NEW.status) THEN
    FOR v_participant IN
      SELECT user_id FROM participations
      WHERE activity_id = NEW.id AND status = 'accepted'
    LOOP
      -- Badge progression always (a solo creator still created an outing)
      PERFORM award_badge_progression(v_participant.user_id, FALSE);
    END LOOP;
    -- rate_participants n'est PLUS émis ici (00427) : la fenêtre de vote
    -- n'ouvre qu'à fin+15 min — l'émission vit dans notify_rate_participants,
    -- appelée par les balayages une fois la fenêtre réellement ouverte.
  END IF;
  RETURN NEW;
END;
$$;

-- ---------- 3. transition_statuses_only (base 00286) : + boucle
-- rate_participants sur la fenêtre [fin+15 min, fin+24 h]. ----------
CREATE OR REPLACE FUNCTION transition_statuses_only()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_activity_id UUID;
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  UPDATE activities
  SET status = 'in_progress', updated_at = now()
  WHERE status = 'published' AND starts_at <= now();

  -- Solo end-of-window: nobody (besides the creator) ever joined → the
  -- outing didn't happen. Must run BEFORE the completed update.
  UPDATE activities
  SET status = 'expired', updated_at = now()
  WHERE status = 'in_progress' AND starts_at + duration <= now()
    AND (SELECT count(*) FROM participations p
         WHERE p.activity_id = activities.id
         AND p.status = 'accepted'
         AND p.user_id != activities.creator_id) = 0;

  UPDATE activities
  SET status = 'completed', updated_at = now()
  WHERE status = 'in_progress' AND starts_at + duration <= now();

  UPDATE activities
  SET status = 'expired', updated_at = now()
  WHERE status = 'published'
    AND starts_at + INTERVAL '2 hours' < now()
    AND (SELECT count(*) FROM participations p
         WHERE p.activity_id = activities.id
         AND p.status = 'accepted'
         AND p.user_id != activities.creator_id) = 0;

  -- Pre-event sweep: published activities approaching start. All three
  -- emitters gate internally on their respective time windows (pre_warning
  -- T-2h..T0, pre_warning_10min T-10..T0, qr_reminder T-10..T0 creator-only).
  FOR v_activity_id IN
    SELECT a.id FROM activities a
    JOIN users c ON c.id = a.creator_id
    WHERE a.status = 'published'
      AND a.requires_presence = TRUE
      AND a.deleted_at IS NULL
      AND c.suspended_at IS NULL
      AND a.starts_at - INTERVAL '2 hours' <= now()
      AND a.starts_at > now()
  LOOP
    PERFORM notify_presence_pre_warning(v_activity_id);
    PERFORM notify_presence_pre_warning_10min(v_activity_id);
    PERFORM notify_creator_qr_reminder(v_activity_id);
  END LOOP;

  -- During-event sweep: in_progress activities. validate_warning gates on
  -- T+duration/2 internally. (qr_create_reminder no longer called here —
  -- moved to the published sweep at T-10min.)
  FOR v_activity_id IN
    SELECT a.id FROM activities a
    JOIN users c ON c.id = a.creator_id
    WHERE a.status = 'in_progress'
      AND a.requires_presence = TRUE
      AND a.deleted_at IS NULL
      AND c.suspended_at IS NULL
  LOOP
    PERFORM notify_presence_validate_warning(v_activity_id);
  END LOOP;

  -- Post-event sweep: completed activities. validate_overdue at T+1h after
  -- end, peer_review_closing at T+22h. Each gates internally.
  FOR v_activity_id IN
    SELECT a.id FROM activities a
    JOIN users c ON c.id = a.creator_id
    WHERE a.status = 'completed'
      AND a.requires_presence = TRUE
      AND a.deleted_at IS NULL
      AND c.suspended_at IS NULL
      AND now() >= a.starts_at + a.duration + INTERVAL '1 hour'
      AND now() <= a.starts_at + a.duration + INTERVAL '24 hours'
  LOOP
    PERFORM notify_presence_validate_overdue(v_activity_id);
    PERFORM notify_peer_review_closing(v_activity_id);
  END LOOP;

  -- 00427: rate_participants only once the vote window is actually OPEN
  -- (end+15min) — the completion trigger no longer emits it at the flip,
  -- where tapping the notification guaranteed a "too early" refusal.
  -- No requires_presence gate: trait/level votes apply to every outing
  -- with >=2 accepted participants. notify_* gates + dedups internally.
  FOR v_activity_id IN
    SELECT a.id FROM activities a
    JOIN users c ON c.id = a.creator_id
    WHERE a.status = 'completed'
      AND a.deleted_at IS NULL
      AND c.suspended_at IS NULL
      AND now() >= a.starts_at + a.duration + INTERVAL '15 minutes'
      AND now() <= a.starts_at + a.duration + INTERVAL '24 hours'
  LOOP
    PERFORM notify_rate_participants(v_activity_id);
  END LOOP;

  PERFORM close_due_presence_windows();
END;
$$;

REVOKE EXECUTE ON FUNCTION transition_statuses_only FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION transition_statuses_only TO postgres;

-- ---------- 4. transition_single_activity (base 00286) : émission lazy au
-- foreground, une fois la fenêtre ouverte (gate interne + dédup). ----------
CREATE OR REPLACE FUNCTION transition_single_activity(
  p_activity_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
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

  SELECT id, creator_id, status, title, starts_at, duration, requires_presence
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN NULL; END IF;
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
      PERFORM notify_presence_reminders(p_activity_id);
      PERFORM notify_creator_qr_reminder(p_activity_id);
    END IF;
  ELSIF v_activity.status = 'in_progress' THEN
    PERFORM notify_presence_reminders(p_activity_id);
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
$$;


REVOKE EXECUTE ON FUNCTION transition_single_activity FROM anon;
GRANT EXECUTE ON FUNCTION transition_single_activity TO authenticated;
