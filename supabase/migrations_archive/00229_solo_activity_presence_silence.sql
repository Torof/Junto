-- Migration 00229: solo activities (1 accepted participant) skip the
-- presence-reminder battery and the auto-FALSE flip on window close.
--
-- Symptom (reported by Scott): a creator alone on their activity with
-- requires_presence=TRUE was bombarded with the full reminder spine
-- (T-2h, T-10min, T+duration/2, T+duration+1h, T+22h) and, 24h later,
-- their confirmed_present was silently flipped to FALSE — dragging
-- their reliability_score down for an activity where there was
-- literally no one to peer-validate them.
--
-- Presence is a peer-trust signal. If you're alone, "absent" is
-- undefined. The fix:
--   - All six presence-notification emitters early-return when
--     accepted_count < 2.
--   - close_presence_window_for skips the auto-FALSE flip when
--     accepted_count < 2; confirmed_present stays NULL (no penalty,
--     no score change).
--   - confirm_presence_via_geo / via_token still work for the lone
--     user — harmless self-attestation, doesn't gain any peer-driven
--     trust signal but doesn't lose anything either.
--
-- Per-function gate (defensive) instead of a single check at the
-- transition layer, so the protection survives any future caller
-- not going through transition_statuses_only.
--
-- Bodies otherwise IDENTICAL to their previous-latest versions
-- (00132 / 00165 / 00148 / 00165 / 00166 / 00166 / 00107).

-- ============================================================================
-- 1. notify_presence_pre_warning (latest 00132) — gate accepted_count >= 2
-- ============================================================================
CREATE OR REPLACE FUNCTION notify_presence_pre_warning(
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
  SELECT id, title, status, starts_at, requires_presence
  INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status != 'published' THEN RETURN; END IF;
  IF now() < v_activity.starts_at - INTERVAL '2 hours' OR now() >= v_activity.starts_at THEN
    RETURN;
  END IF;

  IF (SELECT count(*) FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted') < 2 THEN
    RETURN;
  END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND p.confirmed_present IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'presence_pre_warning'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_pre_warning',
        v_activity.title,
        'Démarre dans 2h — prépare-toi à valider ta présence sur place',
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION
      WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION notify_presence_pre_warning FROM anon, authenticated;

-- ============================================================================
-- 2. notify_presence_pre_warning_10min (latest 00165) — gate
-- ============================================================================
CREATE OR REPLACE FUNCTION notify_presence_pre_warning_10min(
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
  SELECT id, title, status, starts_at, requires_presence
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status NOT IN ('published', 'in_progress') THEN RETURN; END IF;

  IF now() < v_activity.starts_at - INTERVAL '10 minutes' THEN RETURN; END IF;
  IF now() >= v_activity.starts_at THEN RETURN; END IF;

  IF (SELECT count(*) FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted') < 2 THEN
    RETURN;
  END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND p.confirmed_present IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'presence_pre_warning_10min'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_pre_warning_10min',
        v_activity.title,
        'Démarre dans 10 min — pense à valider ta présence sur place',
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION notify_presence_pre_warning_10min FROM anon, authenticated;

-- ============================================================================
-- 3. notify_presence_validate_warning (latest 00148) — gate
-- ============================================================================
CREATE OR REPLACE FUNCTION notify_presence_validate_warning(
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
  SELECT id, title, status, starts_at, duration, requires_presence
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status NOT IN ('in_progress', 'completed') THEN RETURN; END IF;

  IF now() < v_activity.starts_at + (v_activity.duration / 2) THEN RETURN; END IF;
  IF now() >= v_activity.starts_at + v_activity.duration THEN RETURN; END IF;

  IF (SELECT count(*) FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted') < 2 THEN
    RETURN;
  END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND p.confirmed_present IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'presence_validate_warning'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_validate_warning',
        'Attention — valide ta présence',
        'Sinon tu seras enregistré comme absent à ' || v_activity.title,
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION
      WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION notify_presence_validate_warning FROM anon, authenticated;

-- ============================================================================
-- 4. notify_presence_validate_overdue (latest 00165) — gate
-- ============================================================================
CREATE OR REPLACE FUNCTION notify_presence_validate_overdue(
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
  SELECT id, title, status, starts_at, duration, requires_presence
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status != 'completed' THEN RETURN; END IF;

  IF now() < v_activity.starts_at + v_activity.duration + INTERVAL '1 hour' THEN RETURN; END IF;
  IF now() > v_activity.starts_at + v_activity.duration + INTERVAL '1 hour 30 minutes' THEN RETURN; END IF;

  IF (SELECT count(*) FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted') < 2 THEN
    RETURN;
  END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND p.confirmed_present IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'presence_validate_overdue'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_validate_overdue',
        v_activity.title,
        'Tu es enregistré comme absent. Demande à tes co-participants de te valider si tu étais bien là.',
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION notify_presence_validate_overdue FROM anon, authenticated;

-- ============================================================================
-- 5. notify_creator_qr_reminder (latest 00166) — gate
-- ============================================================================
CREATE OR REPLACE FUNCTION notify_creator_qr_reminder(
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_activity RECORD;
BEGIN
  SELECT id, creator_id, title, status, starts_at, requires_presence
  INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status NOT IN ('published', 'in_progress') THEN RETURN; END IF;

  IF now() < v_activity.starts_at - INTERVAL '10 minutes' THEN RETURN; END IF;
  IF now() >= v_activity.starts_at THEN RETURN; END IF;

  IF (SELECT count(*) FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted') < 2 THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM notifications
    WHERE user_id = v_activity.creator_id
      AND type = 'qr_create_reminder'
      AND (data->>'activity_id')::uuid = p_activity_id
  ) THEN RETURN; END IF;

  BEGIN
    PERFORM create_notification(
      v_activity.creator_id,
      'qr_create_reminder',
      v_activity.title,
      'Génère le QR de présence pour tes participants',
      jsonb_build_object('activity_id', p_activity_id)
    );
  EXCEPTION
    WHEN unique_violation THEN NULL;
  END;
END;
$$;

REVOKE EXECUTE ON FUNCTION notify_creator_qr_reminder FROM anon, authenticated;

-- ============================================================================
-- 6. notify_peer_review_closing (latest 00166) — gate
--    (the EXISTS predicate inside already requires another accepted
--    participant, so this gate is technically redundant — but keeping
--    it for symmetry and to short-circuit cheaply.)
-- ============================================================================
CREATE OR REPLACE FUNCTION notify_peer_review_closing(
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
  SELECT id, title, status, starts_at, duration, requires_presence
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.status != 'completed' THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF now() < v_activity.starts_at + v_activity.duration + INTERVAL '22 hours' THEN RETURN; END IF;
  IF now() > v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' THEN RETURN; END IF;

  IF (SELECT count(*) FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted') < 2 THEN
    RETURN;
  END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND p.confirmed_present = TRUE
      AND EXISTS (
        SELECT 1
        FROM participations p2
        WHERE p2.activity_id = p_activity_id
          AND p2.status = 'accepted'
          AND p2.confirmed_present IS NULL
          AND p2.user_id <> p.user_id
          AND NOT EXISTS (
            SELECT 1 FROM peer_validations pv
            WHERE pv.activity_id = p_activity_id
              AND pv.voter_id = p.user_id
              AND pv.voted_id = p2.user_id
          )
      )
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'peer_review_closing'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'peer_review_closing',
        v_activity.title,
        'Dernière chance pour valider tes co-participants — la fenêtre se ferme dans 2h',
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION notify_peer_review_closing FROM anon, authenticated;

-- ============================================================================
-- 7. close_presence_window_for (latest 00107) — skip auto-FALSE for solo
-- ============================================================================
CREATE OR REPLACE FUNCTION close_presence_window_for(
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
  SELECT id, status, starts_at, duration, requires_presence
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.status != 'completed' THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF now() <= v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' THEN RETURN; END IF;

  -- Solo activity (creator alone): "absent" is undefined since there
  -- was no one to peer-validate. Leave confirmed_present=NULL untouched.
  IF (SELECT count(*) FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted') < 2 THEN
    RETURN;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

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

REVOKE EXECUTE ON FUNCTION close_presence_window_for FROM anon, authenticated;
