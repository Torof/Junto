-- Migration 00035: Update transition function to notify participants to rate

CREATE OR REPLACE FUNCTION transition_activity_status()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_activity RECORD;
  v_participant RECORD;
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  -- published → in_progress (starts_at reached)
  UPDATE activities
  SET status = 'in_progress', updated_at = now()
  WHERE status = 'published'
    AND starts_at <= now();

  -- in_progress → completed (starts_at + duration reached)
  FOR v_activity IN
    SELECT id, creator_id, title
    FROM activities
    WHERE status = 'in_progress'
      AND starts_at + duration <= now()
  LOOP
    UPDATE activities SET status = 'completed', updated_at = now() WHERE id = v_activity.id;

    -- Notify creator to confirm presence
    PERFORM create_notification(
      v_activity.creator_id,
      'confirm_presence',
      'Activité terminée',
      'Confirme qui était présent à ' || v_activity.title,
      jsonb_build_object('activity_id', v_activity.id)
    );

    -- Notify all participants to rate each other
    FOR v_participant IN
      SELECT user_id FROM participations
      WHERE activity_id = v_activity.id AND status = 'accepted'
    LOOP
      PERFORM create_notification(
        v_participant.user_id,
        'rate_participants',
        'Évalue tes co-participants',
        'Comment s''est passé ' || v_activity.title || ' ?',
        jsonb_build_object('activity_id', v_activity.id)
      );
    END LOOP;
  END LOOP;

  -- published → expired (starts_at + 2h passed, no participants besides creator)
  UPDATE activities
  SET status = 'expired', updated_at = now()
  WHERE status = 'published'
    AND starts_at + INTERVAL '2 hours' < now()
    AND (SELECT count(*) FROM participations p
         WHERE p.activity_id = activities.id
         AND p.status = 'accepted'
         AND p.user_id != activities.creator_id) = 0;
END;
$$;

REVOKE EXECUTE ON FUNCTION transition_activity_status() FROM anon, authenticated;
