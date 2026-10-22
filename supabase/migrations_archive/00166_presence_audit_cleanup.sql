-- Migration 00166: presence audit cleanup.
--
-- Four targeted fixes from the post-iteration audit:
--
--  1. DROP orphan notify_presence_validate_now (mig 00148 → caller dropped
--     in mig 00165). Function definition retained until now for safety;
--     no caller exists anywhere.
--
--  2. DELETE stale presence_validate_now notification rows. Server stopped
--     emitting in mig 00165 but old rows linger in the table.
--
--  3. Move qr_create_reminder from T0 (in_progress sweep) to T-10min..T0
--     (published sweep). Creator gets the prompt while activity is still
--     published, with enough lead time to generate the QR before the
--     first participant arrives. confirm_presence_via_token already
--     accepts scans from T-15min, so the QR is functionally available
--     at T-10min when the reminder lands.
--
--  4. Fix notify_peer_review_closing gate. Mig 00161 changed the gate
--     from "voter has cast 0 votes" to "voter has at least one
--     CONFIRMED-PRESENT co-participant they haven't voted on" — but
--     that's backwards. Peer voting in the two-vote model is meant to
--     FLIP unconfirmed peers to confirmed. So the reminder should fire
--     when the voter has at least one *unconfirmed* peer they could
--     help flip. Already-confirmed peers don't need more votes (the
--     two-vote threshold is already cleared via geo/QR/peer).

-- ============================================================================
-- 1. + 2. Orphan function + stale rows
-- ============================================================================
DROP FUNCTION IF EXISTS notify_presence_validate_now(UUID);

DELETE FROM notifications
WHERE type = 'presence_validate_now';

-- ============================================================================
-- 3. notify_creator_qr_reminder — moves from in_progress (T0) to
--    published (T-10min..T0). Function recreated verbatim from mig 00113
--    with the status check changed and a new internal time gate.
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

  -- Fire only inside T-10min..T0. Creator's QR button (activity-detail
  -- isInQrWindow) opens at T-15min, so they can act on the reminder
  -- immediately when it lands.
  IF now() < v_activity.starts_at - INTERVAL '10 minutes' THEN RETURN; END IF;
  IF now() >= v_activity.starts_at THEN RETURN; END IF;

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
-- 4. notify_peer_review_closing — gate flips to "voter has unconfirmed
--    peers they can help flip". Function recreated verbatim from mig 00161
--    with one predicate flipped.
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

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND p.confirmed_present = TRUE
      -- At least one OTHER ACCEPTED participant who is NOT yet confirmed
      -- and this voter has not voted on. These are the votes that can
      -- still flip someone via the two-vote threshold; corroborating
      -- already-confirmed peers is lower-value and shouldn't gate the
      -- closing reminder.
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
-- 5. transition_statuses_only — call qr_reminder from the published sweep
--    instead of in_progress. Recreated verbatim from mig 00165 with that
--    one line moved.
-- ============================================================================
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

  PERFORM close_due_presence_windows();
END;
$$;

REVOKE EXECUTE ON FUNCTION transition_statuses_only FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION transition_statuses_only TO postgres;
