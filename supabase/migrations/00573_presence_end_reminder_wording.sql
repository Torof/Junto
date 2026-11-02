-- Wording: « 4 participants n'ont pas encore validé LEUR présence » (00572 said « sa »).

CREATE OR REPLACE FUNCTION public.notify_presence_end_reminder(p_activity_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
  v_missing INTEGER;
BEGIN
  SELECT id, title, status, starts_at, duration, requires_presence, creator_id
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity.id IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status <> 'in_progress' THEN RETURN; END IF;
  IF v_activity.duration < INTERVAL '12 hours' THEN RETURN; END IF;
  IF now() < v_activity.starts_at + v_activity.duration - INTERVAL '1 hour' THEN RETURN; END IF;
  IF now() >= v_activity.starts_at + v_activity.duration THEN RETURN; END IF;

  IF (SELECT count(*) FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted') < 2 THEN
    RETURN;
  END IF;

  SELECT count(*) INTO v_missing
  FROM participations p
  WHERE p.activity_id = p_activity_id AND p.status = 'accepted'
    AND p.confirmed_present IS NULL AND p.user_id <> v_activity.creator_id;
  IF v_missing = 0 THEN RETURN; END IF;

  FOR v_target IN
    SELECT p.user_id FROM participations p
    WHERE p.activity_id = p_activity_id AND p.status = 'accepted'
      AND p.confirmed_present IS NULL AND p.user_id <> v_activity.creator_id
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.user_id = p.user_id AND n.type = 'presence_end_reminder'
          AND (n.data->>'activity_id')::uuid = p_activity_id
      )
  LOOP
    BEGIN
      PERFORM create_notification(
        v_target.user_id,
        'presence_end_reminder',
        'Fin de sortie : valide ta présence',
        'Scanne le QR de l''organisateur — valable jusqu''à 3 h après la fin de « ' || v_activity.title || ' ».',
        jsonb_build_object('activity_id', p_activity_id, 'params', jsonb_build_object('title', v_activity.title))
      );
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1 FROM notifications n
    WHERE n.user_id = v_activity.creator_id AND n.type = 'presence_end_reminder'
      AND (n.data->>'activity_id')::uuid = p_activity_id
  ) THEN
    BEGIN
      PERFORM create_notification(
        v_activity.creator_id,
        'presence_end_reminder',
        'Fin de sortie : affiche ton QR',
        v_missing || CASE WHEN v_missing > 1
                          THEN ' participants n''ont pas encore validé leur présence'
                          ELSE ' participant n''a pas encore validé sa présence' END
          || ' sur « ' || v_activity.title || ' ».',
        jsonb_build_object('activity_id', p_activity_id, 'variant', 'creator',
          'params', jsonb_build_object('title', v_activity.title, 'count', v_missing))
      );
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END IF;
END;
$$;
