-- A requester who blocks the organiser withdraws their pending request instead
-- of having it marked « refused » (audit, small 12): the refusal was recorded
-- as the organiser's decision although the organiser did nothing.

CREATE OR REPLACE FUNCTION public.cascade_block_cleanup()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_row RECORD;
  v_name TEXT;
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  -- 00522 (F2): a pending request of someone who is now in a block relation
  -- with an accepted member of that outing is withdrawn (it could never be
  -- accepted any more — the shared-outing rule would refuse it).
  -- 00523 (Scott, F2): the organiser is told that a block withdrew it — never
  -- who. Not when the organiser is a party (the refusal below covers it).
  FOR v_row IN
    UPDATE participations p
    SET status = 'withdrawn'
    FROM activities a
    WHERE a.id = p.activity_id
      AND p.status = 'pending'
      AND a.creator_id NOT IN (NEW.blocker_id, NEW.blocked_id)
      AND ((p.user_id = NEW.blocked_id AND EXISTS (SELECT 1 FROM participations q
              WHERE q.activity_id = p.activity_id AND q.user_id = NEW.blocker_id AND q.status = 'accepted'))
        OR (p.user_id = NEW.blocker_id AND EXISTS (SELECT 1 FROM participations q
              WHERE q.activity_id = p.activity_id AND q.user_id = NEW.blocked_id AND q.status = 'accepted')))
    RETURNING p.activity_id, p.user_id, a.creator_id, a.title
  LOOP
    SELECT display_name INTO v_name FROM public_profiles WHERE id = v_row.user_id;
    PERFORM create_notification(
      v_row.creator_id,
      'join_request_blocked',
      'Demande retirée',
      'La demande de ' || coalesce(v_name, 'quelqu''un') || ' pour « ' || v_row.title || ' » a été retirée : un blocage l''oppose à un participant.',
      jsonb_build_object('activity_id', v_row.activity_id,
        'params', jsonb_build_object('name', coalesce(v_name, 'Quelqu''un'), 'title', v_row.title))
    );
  END LOOP;

  -- The organiser who blocks a requester refuses their pending request.
  UPDATE participations p
  SET status = 'refused', refused_at = now()
  FROM activities a
  WHERE p.activity_id = a.id
    AND p.status = 'pending'
    AND a.creator_id = NEW.blocker_id AND p.user_id = NEW.blocked_id;
  -- 00541: a requester who blocks the organiser withdraws their own request —
  -- a refusal would be recorded against them as the organiser's decision.
  UPDATE participations p
  SET status = 'withdrawn'
  FROM activities a
  WHERE p.activity_id = a.id
    AND p.status = 'pending'
    AND a.creator_id = NEW.blocked_id AND p.user_id = NEW.blocker_id;

  -- Cancel pending/accepted seat requests in both directions
  UPDATE seat_requests
  SET status = 'cancelled'
  WHERE status IN ('pending', 'accepted')
    AND ((requester_id = NEW.blocker_id AND driver_id = NEW.blocked_id)
      OR (requester_id = NEW.blocked_id AND driver_id = NEW.blocker_id));

  RETURN NEW;
END;
$function$;
