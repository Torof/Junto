-- 00498 — check_schedule_conflict : les écritures système (sans utilisateur) ne sont pas contrôlées.

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
  -- System writes (scheduled jobs, demo seeding) have no end user.
  IF auth.uid() IS NULL THEN RETURN NEW; END IF;
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
