-- Migration 00265: two presence-notification fixes (reported by Scott).
--
-- (1) BUG: solo activities still received 'rate_participants' ("Évalue
--     tes co-participants") even with nobody to rate. The completion
--     trigger on_activity_completed_award_badges (00136) loops over
--     accepted participants with NO accepted_count gate — the 00229
--     sweep gated the six presence emitters but this one lives in the
--     badge trigger and slipped through. Fix: keep awarding badges for
--     everyone (a solo creator still "created"), but only emit
--     rate_participants when there are ≥2 accepted participants.
--
-- (2) GAP: a still-unvalidated attendee only ever got nudged at end+1h
--     (presence_validate_overdue). If they miss or dismiss it, they
--     never learn their presence didn't register before the end+24h
--     auto-FALSE penalty — "they may never come back to the finished
--     activity and realise their presence wasn't validated" (Scott).
--     Fix: a NEW 'presence_validate_final' last-chance push at end+22h,
--     to the unconfirmed users THEMSELVES (only on activities with
--     peers, ≥2 accepted — solo is penalty-exempt). Routes via
--     activity_id to the activity screen, where the peer-review
--     backstop banner now lives. Emitted from notify_peer_review_closing
--     (already runs at end+22h..end+24h, solo-gated, cron-driven).

-- ============================================================================
-- 1. Completion trigger — gate rate_participants for solo
-- ============================================================================
CREATE OR REPLACE FUNCTION on_activity_completed_award_badges()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_participant RECORD;
  v_accepted_count INTEGER;
BEGIN
  IF NEW.status = 'completed' AND (OLD.status IS DISTINCT FROM NEW.status) THEN
    SELECT count(*) INTO v_accepted_count
    FROM participations
    WHERE activity_id = NEW.id AND status = 'accepted';

    FOR v_participant IN
      SELECT user_id FROM participations
      WHERE activity_id = NEW.id AND status = 'accepted'
    LOOP
      -- Badge progression always (a solo creator still created an outing)
      PERFORM award_badge_progression(v_participant.user_id, FALSE);

      -- Peer review prompt only when there's actually someone to rate.
      IF v_accepted_count >= 2 THEN
        PERFORM create_notification(
          v_participant.user_id,
          'rate_participants',
          'Évalue tes co-participants',
          'Comment s''est passé ' || NEW.title || ' ?',
          jsonb_build_object('activity_id', NEW.id)
        );
      END IF;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION on_activity_completed_award_badges FROM anon, authenticated;

-- ============================================================================
-- 2. notify_peer_review_closing — keep the voter nudge, ADD the
--    last-chance warning to the unconfirmed attendees themselves
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

  -- (a) Nudge confirmed peers who still have someone to vouch for.
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

  -- (b) NEW: warn the still-unconfirmed attendees themselves, before the
  --     end+24h auto-FALSE penalty. They may never reopen the activity.
  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND p.confirmed_present IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id
          AND n.type = 'presence_validate_final'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_validate_final',
        v_activity.title,
        'Ta présence n''a pas été validée. Demande à un participant présent de te confirmer avant que ça compte comme une absence — fenêtre fermée dans 2h.',
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION notify_peer_review_closing FROM anon, authenticated;
