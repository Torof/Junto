-- ============================================================================
-- 00516 — Re-sécurisation, lot sorties (audit neuf).
-- M1  Piège de l'annulation tardive : une place acceptée à moins de 12 h du
--     départ (ou d'un organisateur suspendu) ne compte plus comme annulation
--     tardive si on la quitte ; les demandeurs en attente sont prévenus quand
--     la sortie change. Colonne participations.accepted_at (déclencheur).
-- L1  La durée est figée dès qu'il y a des participants.
-- L3  Sortie retirée par la modération : ni acceptation, ni refus, ni
--     annulation, ni liste de participants.
-- L4  Coordonnées réelles exigées (NaN et hors bornes refusés).
-- L5  Transport et levée de pénalité limités (20 / min).
-- L6  Plus d'entrée dans une sortie avec présence après départ + 15 min.
-- L7  Trophées, réputation, votants : rien pour un compte suspendu ; date
--     des votes au mois.
-- ============================================================================

ALTER TABLE participations ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ;
SELECT set_config('junto.bypass_lock', 'true', true);
UPDATE participations SET accepted_at = created_at WHERE status = 'accepted' AND accepted_at IS NULL;
SELECT set_config('junto.bypass_lock', 'false', true);

CREATE OR REPLACE FUNCTION private.stamp_accepted_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status = 'accepted' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'accepted') THEN
    NEW.accepted_at := now();
  ELSIF TG_OP = 'UPDATE' THEN
    NEW.accepted_at := CASE WHEN NEW.status = 'accepted' THEN OLD.accepted_at END;
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION private.stamp_accepted_at() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_participations_accepted_at ON participations;
CREATE TRIGGER trg_participations_accepted_at BEFORE INSERT OR UPDATE OF status ON participations
  FOR EACH ROW EXECUTE FUNCTION private.stamp_accepted_at();

CREATE OR REPLACE FUNCTION public.leave_activity(p_activity_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_participation RECORD;
  v_activity RECORD;
  v_user_name TEXT;
  v_is_late BOOLEAN;
  v_reason TEXT;
  v_was_driver BOOLEAN;
  v_passenger RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_reason := NULLIF(left(trim(coalesce(p_reason, '')), 200), '');

  SELECT p.id, p.status, p.transport_type, p.transport_seats, p.accepted_at
  INTO v_participation
  FROM participations p
  WHERE p.activity_id = p_activity_id AND p.user_id = v_user_id
  FOR UPDATE;

  IF v_participation IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF v_participation.status NOT IN ('accepted', 'pending') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, status, starts_at, creator_id, title, requires_presence INTO v_activity
  FROM activities WHERE id = p_activity_id;

  -- Block creator from leaving their own activity (would orphan the activity)
  IF v_user_id = v_activity.creator_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00477 (PR-5): only leaving an ACCEPTED place late is a late cancel;
  -- withdrawing a request nobody answered is not.
  v_is_late := v_participation.status = 'accepted'
               AND v_activity.requires_presence
               AND (v_activity.starts_at - INTERVAL '12 hours' < now())
               -- 00516: only a place held since before the 12-hour line — an
               -- organiser accepting a request at the last minute cannot make
               -- leaving count as late.
               AND (v_participation.accepted_at IS NULL OR v_participation.accepted_at < v_activity.starts_at - INTERVAL '12 hours')
               -- 00516: nobody is penalised for leaving a suspended organiser's outing.
               AND NOT private.user_is_suspended(v_activity.creator_id);

  v_was_driver := v_participation.transport_type IN ('car', 'carpool');

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET status = 'withdrawn',
      left_at = now(),
      left_reason = v_reason,
      transport_type = NULL,
      transport_seats = NULL,
      transport_from_name = NULL,
      transport_departs_at = NULL
  WHERE id = v_participation.id;

  -- 00478 (PR-4): the late cancel goes to its own ledger, which no rejoin,
  -- re-invitation, declined invitation or block cascade can erase. A new late
  -- cancel on the same outing re-arms a previous waiver.
  IF v_is_late THEN
    INSERT INTO late_cancels (user_id, activity_id, at, waived)
    VALUES (v_user_id, p_activity_id, now(), false)
    ON CONFLICT (user_id, activity_id) DO UPDATE SET at = now(), waived = false;
  END IF;

  PERFORM recalculate_reliability_score(v_user_id);

  SELECT display_name INTO v_user_name FROM users WHERE id = v_user_id;
  -- 00477/00478 (AB-1): at most one notification of EACH type per participant
  -- and outing per 24 h — an early leave never hides a later late one.
  IF NOT EXISTS (
    SELECT 1 FROM notifications
    WHERE user_id = v_activity.creator_id
      AND type = CASE WHEN v_is_late THEN 'participant_left_late' ELSE 'participant_left' END
      AND data->>'participation_id' = v_participation.id::text
      AND created_at > now() - INTERVAL '24 hours'
  ) THEN
  PERFORM create_notification(
    v_activity.creator_id,
    CASE WHEN v_is_late THEN 'participant_left_late' ELSE 'participant_left' END,
    coalesce(v_user_name, 'Quelqu''un') || ' a quitté « ' || v_activity.title || ' »',
    CASE
      WHEN v_is_late THEN 'Départ tardif — pénalité de fiabilité appliquée, tu peux la lever depuis la sortie.'
      ELSE coalesce(v_reason, '')
    END,
    jsonb_build_object('activity_id', p_activity_id, 'participation_id', v_participation.id, 'late', v_is_late,
      'params', jsonb_build_object('name', coalesce(v_user_name, 'Quelqu''un'), 'title', v_activity.title, 'reason', coalesce(v_reason, '')))
  );
  END IF;

  -- If the leaver was offering rides, cancel their pending/accepted seat_requests
  -- and notify each affected requester so they can find another ride.
  IF v_was_driver THEN
    FOR v_passenger IN
      SELECT id, requester_id FROM seat_requests
      WHERE activity_id = p_activity_id AND driver_id = v_user_id
        AND status IN ('pending', 'accepted')
    LOOP
      UPDATE seat_requests SET status = 'cancelled' WHERE id = v_passenger.id;
      PERFORM create_notification(
        v_passenger.requester_id,
        'driver_left',
        'Place annulée',
        coalesce(v_user_name, 'Le conducteur') || ' a quitté « ' || v_activity.title || ' » — trouve une autre place',
        jsonb_build_object('activity_id', p_activity_id, 'driver_id', v_user_id,
          'params', jsonb_build_object('name', coalesce(v_user_name, 'Le conducteur'), 'title', v_activity.title))
      );
    END LOOP;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.handle_activity_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF current_setting('junto.bypass_lock', true) = 'true' THEN
    NEW.updated_at := now();
    RETURN NEW;
  END IF;

  NEW.creator_id := OLD.creator_id;
  NEW.status := OLD.status;
  NEW.invite_token := OLD.invite_token;
  NEW.created_at := OLD.created_at;
  NEW.deleted_at := OLD.deleted_at;
  NEW.cancelled_reason := OLD.cancelled_reason;
  NEW.distance_km := OLD.distance_km;
  NEW.elevation_gain_m := OLD.elevation_gain_m;
  NEW.meeting_name := OLD.meeting_name;
  NEW.trace_geojson := OLD.trace_geojson;
  NEW.route := OLD.route;
  NEW.is_demo := OLD.is_demo;

  IF (SELECT count(*) FROM participations
      WHERE activity_id = NEW.id AND status = 'accepted' AND user_id != OLD.creator_id) > 0
  THEN
    NEW.location_meeting := OLD.location_meeting;
    NEW.location_end := OLD.location_end;
    NEW.location_objective := OLD.location_objective;
    NEW.objective_name := OLD.objective_name;
    NEW.starts_at := OLD.starts_at;
    NEW.level := OLD.level;
    NEW.level_max := OLD.level_max;
    NEW.max_participants := OLD.max_participants;
    NEW.visibility := OLD.visibility;
    NEW.requires_presence := OLD.requires_presence;
    -- 00516: nor its length (participants' schedules and the conflict rule
    -- depend on it).
    NEW.duration := OLD.duration;
  END IF;

  -- 00467 (audit M1): once the outing has started, its end is fixed — the
  -- presence QR window and the absence finalizer both hang off it.
  IF now() >= OLD.starts_at THEN
    NEW.duration := OLD.duration;
  END IF;

  -- 00441: the locality follows the meeting pin and nothing else — it may
  -- only change in the same UPDATE that moves location_meeting (which the
  -- participant lock above already freezes once someone has joined).
  IF NEW.location_meeting IS NOT DISTINCT FROM OLD.location_meeting THEN
    NEW.meeting_locality := OLD.meeting_locality;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.accept_participation(p_participation_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_participation RECORD;
  v_max_participants INTEGER;
  v_activity_status TEXT;
  v_current_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT p.id, p.activity_id, p.user_id, p.status, a.creator_id, a.status AS activity_status, a.title
  INTO v_participation
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.id = p_participation_id
  FOR UPDATE OF p;

  IF v_participation IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_participation.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00516: not on an outing removed by moderation, nor once the presence
  -- check window of a started outing has passed.
  IF EXISTS (SELECT 1 FROM activities a WHERE a.id = v_participation.activity_id
             AND (a.deleted_at IS NOT NULL OR (a.requires_presence AND now() > a.starts_at + INTERVAL '15 minutes'))) THEN
    RAISE EXCEPTION 'junto.activity_locked';
  END IF;
  IF v_participation.activity_status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_participation.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Lock the activity row and re-read cap AND status under the lock:
  -- serializes concurrent accepts with each other, with join_activity
  -- (same lock), with update_activity lowering the cap, and with
  -- cancel_activity flipping the status (00311 re-read the cap only —
  -- an accept racing a cancel could accept into a cancelled activity).
  SELECT max_participants, status INTO v_max_participants, v_activity_status
  FROM activities WHERE id = v_participation.activity_id
  FOR UPDATE;

  IF v_activity_status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT count(*) INTO v_current_count
  FROM participations
  WHERE activity_id = v_participation.activity_id AND status = 'accepted';

  -- Open activities (max_participants IS NULL) honor a hidden 50-soft-cap, same as join_activity
  IF v_current_count >= COALESCE(v_max_participants, 50) THEN
    RAISE EXCEPTION 'junto.activity_full';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations SET status = 'accepted' WHERE id = p_participation_id;

  PERFORM create_notification(
    v_participation.user_id,
    'request_accepted',
    'Tu es dans la sortie !',
    '« ' || v_participation.title || ' »',
    jsonb_build_object('activity_id', v_participation.activity_id,
      'params', jsonb_build_object('title', v_participation.title))
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.refuse_participation(p_participation_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_participation RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT p.id, p.user_id, p.status, p.activity_id, a.creator_id, a.status AS activity_status, a.title
  INTO v_participation
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.id = p_participation_id
  FOR UPDATE OF p;

  IF v_participation IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_participation.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM activities a WHERE a.id = v_participation.activity_id AND a.deleted_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';  -- 00516: moderated outing frozen
  END IF;
  IF v_participation.activity_status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_participation.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET status = 'refused', refused_at = now()
  WHERE id = p_participation_id;

  PERFORM create_notification(
    v_participation.user_id,
    'request_refused',
    'Demande refusée',
    '« ' || v_participation.title || ' »',
    jsonb_build_object('activity_id', v_participation.activity_id,
      'params', jsonb_build_object('title', v_participation.title))
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_activity(p_activity_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_participant RECORD;
  v_clean_reason TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00472/00474 (audit L11, F9): bounded to 300 — copied into every participant's
  -- notification, twice in the push payload (body + params), under Expo's 4 KB.
  v_clean_reason := left(NULLIF(trim(coalesce(p_reason, '')), ''), 300);
  IF v_clean_reason IS NULL OR char_length(v_clean_reason) < 3 THEN
    RAISE EXCEPTION 'junto.cancel_reason_invalid';
  END IF;

  SELECT id, creator_id, status, title
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id
  FOR UPDATE;

  IF v_activity IS NULL OR v_user_id != v_activity.creator_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM activities a WHERE a.id = p_activity_id AND a.deleted_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';  -- 00516: moderated outing frozen
  END IF;
  IF v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE activities
  SET status = 'cancelled',
      cancelled_reason = v_clean_reason,
      updated_at = now()
  WHERE id = p_activity_id;

  -- Notify all accepted participants except creator
  FOR v_participant IN
    SELECT user_id FROM participations
    WHERE activity_id = p_activity_id
      AND status IN ('accepted', 'pending')
      AND user_id != v_user_id
  LOOP
    PERFORM create_notification(
      v_participant.user_id,
      'activity_cancelled',
      'Sortie annulée',
      CASE WHEN coalesce(v_clean_reason, '') = '' THEN '« ' || v_activity.title || ' »'
           ELSE '« ' || v_activity.title || ' » — ' || v_clean_reason END,
      jsonb_build_object('activity_id', p_activity_id,
        'variant', CASE WHEN coalesce(v_clean_reason, '') = '' THEN 'no_reason' ELSE NULL END,
        'params', jsonb_build_object('title', v_activity.title, 'reason', coalesce(v_clean_reason, '')))
    );
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_activity_participants(p_activity_id uuid)
 RETURNS TABLE(participation_id uuid, activity_id uuid, user_id uuid, status text, created_at timestamp with time zone, left_at timestamp with time zone, confirmed_present boolean, transport_type text, transport_seats smallint, transport_from_name text, transport_departs_at timestamp with time zone, transport_from_lat double precision, transport_from_lng double precision, display_name text, avatar_url text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_is_creator BOOLEAN;
  v_is_member BOOLEAN;
  v_live BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities a
    WHERE a.id = p_activity_id
      -- 00472 (audit L3): the demo curtain, like every other read surface.
      AND (a.is_demo = false OR demo_content_visible())
      AND a.deleted_at IS NULL  -- 00516
      AND (
        a.visibility IN ('public', 'approval')
        OR a.creator_id = v_user_id
        -- 00485 (AC-2): only an ACCEPTED participant, not a removed / left one.
        OR EXISTS (
          SELECT 1 FROM participations p
          WHERE p.activity_id = a.id AND p.user_id = v_user_id AND p.status = 'accepted'
        )
      )
  ) THEN
    RETURN;
  END IF;

  SELECT a.creator_id = v_user_id, a.status IN ('published', 'in_progress')
    INTO v_is_creator, v_live
  FROM activities a WHERE a.id = p_activity_id;
  v_is_member := v_is_creator OR EXISTS (
    SELECT 1 FROM participations p
    WHERE p.activity_id = p_activity_id AND p.user_id = v_user_id AND p.status = 'accepted');

  RETURN QUERY
  SELECT
    p.id AS participation_id,
    p.activity_id,
    p.user_id,
    p.status,
    p.created_at,
    p.left_at,
    -- 00485 (DX-1): an absence is shown only to the organiser and to the
    -- person concerned; everyone else sees « present » or nothing.
    CASE WHEN p.user_id = v_user_id OR v_is_creator THEN p.confirmed_present
         -- 00488: only fellow members see « present » (once an outing is
         -- finalised, a missing tick would otherwise read as an absence).
         WHEN v_is_member AND p.confirmed_present THEN true ELSE NULL END,
    -- 00490: per-person transport for members only (places are public in
    -- the transport summary; who leaves from where is not).
    CASE WHEN p.user_id = v_user_id OR v_is_member THEN p.transport_type END,
    -- 00490: per-person transport for members only (places are public in
    -- the transport summary; who leaves from where is not).
    CASE WHEN p.user_id = v_user_id OR v_is_member THEN p.transport_seats END,
    -- 00485 (AC-2): a driver's starting point (often home) is shown only to
    -- the outing's accepted members, while it is upcoming / under way, and
    -- never across a block.
    CASE WHEN (p.user_id = v_user_id OR (v_is_member AND v_live AND NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE (b.blocker_id = v_user_id AND b.blocked_id = p.user_id)
         OR (b.blocker_id = p.user_id AND b.blocked_id = v_user_id)))) THEN p.transport_from_name END,
    -- 00490: per-person transport for members only (places are public in
    -- the transport summary; who leaves from where is not).
    CASE WHEN p.user_id = v_user_id OR v_is_member THEN p.transport_departs_at END,
    CASE WHEN (p.user_id = v_user_id OR (v_is_member AND v_live AND NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE (b.blocker_id = v_user_id AND b.blocked_id = p.user_id)
         OR (b.blocker_id = p.user_id AND b.blocked_id = v_user_id)))) THEN p.transport_from_lat END,
    CASE WHEN (p.user_id = v_user_id OR (v_is_member AND v_live AND NOT EXISTS (
      SELECT 1 FROM blocked_users b
      WHERE (b.blocker_id = v_user_id AND b.blocked_id = p.user_id)
         OR (b.blocker_id = p.user_id AND b.blocked_id = v_user_id)))) THEN p.transport_from_lng END,
    pp.display_name,
    pp.avatar_url
  FROM participations p
  JOIN public_profiles pp ON pp.id = p.user_id
  WHERE p.activity_id = p_activity_id
    AND p.status = 'accepted'
    AND p.user_id NOT IN (
      SELECT blocked_id FROM blocked_users WHERE blocker_id = v_user_id
    )
  ORDER BY p.created_at;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_activity(p_sport_id uuid, p_title text, p_description text, p_level text, p_max_participants integer, p_meeting_lng double precision, p_meeting_lat double precision, p_end_lng double precision DEFAULT NULL::double precision, p_end_lat double precision DEFAULT NULL::double precision, p_starts_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_duration text DEFAULT '2 hours'::text, p_visibility text DEFAULT 'public'::text, p_requires_presence boolean DEFAULT true, p_objective_lng double precision DEFAULT NULL::double precision, p_objective_lat double precision DEFAULT NULL::double precision, p_objective_name text DEFAULT NULL::text, p_distance_km numeric DEFAULT NULL::numeric, p_elevation_gain_m integer DEFAULT NULL::integer, p_meeting_name text DEFAULT NULL::text, p_trace_geojson jsonb DEFAULT NULL::jsonb, p_level_max text DEFAULT NULL::text, p_meeting_locality text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_tier TEXT;
  v_is_admin BOOLEAN;
  v_daily_count INTEGER;
  v_monthly_count INTEGER;
  v_activity_id UUID;
  v_title TEXT;
  v_level_max TEXT;
  v_distance_km NUMERIC;
  v_elevation_gain_m INTEGER;
BEGIN
  -- Sensitive: generic.
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00516: coordinates must be real places (NaN and out-of-range refused).
  IF NOT ((p_meeting_lng IS NULL AND p_meeting_lat IS NULL) OR (p_meeting_lng BETWEEN -180 AND 180 AND p_meeting_lat BETWEEN -90 AND 90)) OR p_meeting_lng IS NULL
     OR NOT ((p_end_lng IS NULL AND p_end_lat IS NULL) OR (p_end_lng BETWEEN -180 AND 180 AND p_end_lat BETWEEN -90 AND 90))
     OR NOT ((p_objective_lng IS NULL AND p_objective_lat IS NULL) OR (p_objective_lng BETWEEN -180 AND 180 AND p_objective_lat BETWEEN -90 AND 90)) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- User-actionable: coded.
  v_title := trim(p_title);
  IF char_length(v_title) < 3 THEN RAISE EXCEPTION 'junto.title_too_short'; END IF;

  -- Normalise the range high end: empty → NULL; equal to the low end → NULL
  -- (single level). Scale membership/ordering enforced client-side.
  v_level_max := NULLIF(trim(coalesce(p_level_max, '')), '');
  IF v_level_max = trim(p_level) THEN v_level_max := NULL; END IF;

  IF p_starts_at IS NULL OR p_starts_at <= NOW() THEN
    RAISE EXCEPTION 'junto.date_in_past';
  END IF;

  IF p_starts_at > NOW() + INTERVAL '6 months' THEN
    RAISE EXCEPTION 'junto.date_too_far';
  END IF;

  IF p_max_participants IS NOT NULL AND (p_max_participants < 2 OR p_max_participants > 50) THEN
    RAISE EXCEPTION 'junto.participants_range';
  END IF;

  -- Tamper guard (UI only sends valid values): generic.
  IF p_visibility NOT IN ('public', 'approval', 'private_link', 'private_link_approval') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00470 (audit M6): the trace is validated before anything else touches it.
  IF p_trace_geojson IS NOT NULL AND NOT trace_geojson_ok(p_trace_geojson) THEN
    RAISE EXCEPTION 'junto.trace_geojson_invalid';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_create_activity'));

  SELECT tier, coalesce(is_admin, FALSE) INTO v_tier, v_is_admin
  FROM users WHERE id = v_user_id;

  -- Private-link visibilities are open to everyone (Scott 2026-07-10):
  -- all tiers are free at launch. Premium gate removed.

  IF NOT v_is_admin THEN
    SELECT count(*) INTO v_daily_count
    FROM activities
    WHERE creator_id = v_user_id AND created_at > NOW() - INTERVAL '1 day';

    IF v_daily_count >= 10 THEN RAISE EXCEPTION 'junto.limit_daily'; END IF;

    SELECT count(*) INTO v_monthly_count
    FROM activities
    WHERE creator_id = v_user_id AND created_at > NOW() - INTERVAL '30 days';

    IF v_monthly_count >= 30 THEN RAISE EXCEPTION 'junto.limit_monthly'; END IF;
  END IF;

  -- Trace-derived prefill (00452), after the rate limits (00470, audit L7):
  -- the typed value always wins; a derived figure outside the column's range
  -- (flat or descending trace → 0 m, degenerate or absurd distance) stays
  -- NULL instead of failing the insert (00470, audit M5).
  v_distance_km := p_distance_km;
  v_elevation_gain_m := p_elevation_gain_m;
  IF p_trace_geojson IS NOT NULL THEN
    IF v_distance_km IS NULL THEN
      v_distance_km := trace_distance_km(p_trace_geojson);
      IF round(v_distance_km, 1) <= 0 OR v_distance_km > 9999 THEN v_distance_km := NULL; END IF;
    END IF;
    IF v_elevation_gain_m IS NULL THEN
      v_elevation_gain_m := NULLIF(trace_elevation_gain_m(p_trace_geojson), 0);
      IF v_elevation_gain_m > 99999 THEN v_elevation_gain_m := NULL; END IF;
    END IF;
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  INSERT INTO activities (
    creator_id, sport_id, title, description, level, level_max,
    max_participants, location_meeting, location_end,
    location_objective, objective_name, meeting_name, meeting_locality,
    distance_km, elevation_gain_m,
    starts_at, duration, visibility, requires_presence,
    trace_geojson,
    status, created_at, updated_at
  ) VALUES (
    v_user_id, p_sport_id, v_title, trim(p_description), p_level, v_level_max,
    p_max_participants,
    ST_SetSRID(ST_MakePoint(p_meeting_lng, p_meeting_lat), 4326)::geography,
    CASE WHEN p_end_lng IS NOT NULL AND p_end_lat IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_end_lng, p_end_lat), 4326)::geography
      ELSE NULL END,
    CASE WHEN p_objective_lng IS NOT NULL AND p_objective_lat IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_objective_lng, p_objective_lat), 4326)::geography
      ELSE NULL END,
    CASE WHEN p_objective_name IS NOT NULL AND char_length(trim(p_objective_name)) > 0
      THEN trim(p_objective_name) ELSE NULL END,
    CASE WHEN p_meeting_name IS NOT NULL AND char_length(trim(p_meeting_name)) > 0
      THEN trim(p_meeting_name) ELSE NULL END,
    CASE WHEN p_meeting_locality IS NOT NULL AND char_length(trim(p_meeting_locality)) > 0
      THEN left(trim(p_meeting_locality), 80) ELSE NULL END,
    v_distance_km,
    v_elevation_gain_m,
    p_starts_at, p_duration::interval, p_visibility, coalesce(p_requires_presence, TRUE),
    p_trace_geojson,
    'published', now(), now()
  ) RETURNING id INTO v_activity_id;

  INSERT INTO participations (activity_id, user_id, status, created_at)
  VALUES (v_activity_id, v_user_id, 'accepted', now());

  IF p_visibility IN ('public', 'approval') THEN
    PERFORM check_alerts_for_activity(v_activity_id);
  END IF;

  RETURN v_activity_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_activity(p_activity_id uuid, p_title text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_level text DEFAULT NULL::text, p_max_participants integer DEFAULT NULL::integer, p_meeting_lng double precision DEFAULT NULL::double precision, p_meeting_lat double precision DEFAULT NULL::double precision, p_starts_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_duration text DEFAULT NULL::text, p_visibility text DEFAULT NULL::text, p_level_max text DEFAULT NULL::text, p_meeting_locality text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_old RECORD;
  v_new RECORD;
  v_participant RECORD;
  v_trimmed_title TEXT;
  v_level_max TEXT;
  v_changes JSONB;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00516: coordinates must be real places.
  IF NOT ((p_meeting_lng IS NULL AND p_meeting_lat IS NULL) OR (p_meeting_lng BETWEEN -180 AND 180 AND p_meeting_lat BETWEEN -90 AND 90)) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00480: frequency cap (audit, counter-review of phase B).
  PERFORM private.rate_hit('activity_update', 30, INTERVAL '1 hour');

  IF p_title IS NOT NULL THEN
    v_trimmed_title := trim(p_title);
    IF char_length(v_trimmed_title) < 3 THEN RAISE EXCEPTION 'junto.title_too_short'; END IF;
  END IF;

  -- Normalised range high end (only applied when the level is being edited).
  v_level_max := NULLIF(trim(coalesce(p_level_max, '')), '');
  IF p_level IS NOT NULL AND v_level_max = trim(p_level) THEN v_level_max := NULL; END IF;

  SELECT id, creator_id, status, title, description, starts_at, duration,
         location_meeting, max_participants, level, visibility, deleted_at
  INTO v_old FROM activities WHERE id = p_activity_id FOR UPDATE;

  IF v_old IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_old.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_old.status NOT IN ('published', 'in_progress') THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00494 (BR-8): an outing removed by moderation is frozen.
  IF v_old.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- The client resends starts_at as an ISO string (millisecond precision)
  -- while Postgres stores microseconds — a raw IS DISTINCT FROM would see a
  -- sub-millisecond ghost diff on any row whose date has non-zero µs (seed,
  -- manual INSERTs) and re-trigger the date_in_past bug plus phantom
  -- "activity updated" notifs. Normalise: an unchanged-at-ms-precision date
  -- is treated as "not provided" for everything downstream (validation,
  -- UPDATE, change diff).
  IF p_starts_at IS NOT NULL
     AND date_trunc('milliseconds', p_starts_at) IS NOT DISTINCT FROM date_trunc('milliseconds', v_old.starts_at) THEN
    p_starts_at := NULL;
  END IF;

  -- Only validate the date when it actually changes — resending the
  -- unchanged (now past) starts_at of an in-progress activity is not a
  -- reschedule and must not block editing the other fields.
  -- 00503: the organiser cannot move their outing onto a slot where they are
  -- already accepted elsewhere (participants are told of the change).
  IF (p_starts_at IS NOT NULL OR p_duration IS NOT NULL) AND NOT EXISTS (
       SELECT 1 FROM activities x WHERE x.id = p_activity_id AND x.is_demo) AND EXISTS (
    SELECT 1 FROM participations p JOIN activities a ON a.id = p.activity_id
    WHERE p.user_id = v_user_id AND p.status = 'accepted' AND p.activity_id <> p_activity_id
      AND a.status IN ('published', 'in_progress') AND a.deleted_at IS NULL AND NOT a.is_demo
      AND tstzrange(a.starts_at, a.starts_at + a.duration)
          && tstzrange(coalesce(p_starts_at, v_old.starts_at),
                       coalesce(p_starts_at, v_old.starts_at) + coalesce(p_duration::interval, v_old.duration))
  ) THEN
    RAISE EXCEPTION 'junto.schedule_conflict';
  END IF;

  -- 00494 (BR-7): once under way, an outing's date no longer moves (it
  -- would leave « in progress » with a future start).
  IF p_starts_at IS NOT NULL AND v_old.status = 'in_progress' THEN
    RAISE EXCEPTION 'junto.activity_locked';
  END IF;
  -- 00496 (BR-7): nor its duration (the app locks it; the server too).
  IF p_duration IS NOT NULL AND v_old.status = 'in_progress'
     AND p_duration::interval IS DISTINCT FROM v_old.duration THEN
    RAISE EXCEPTION 'junto.activity_locked';
  END IF;
  IF p_starts_at IS NOT NULL THEN
    IF p_starts_at <= NOW() THEN
      RAISE EXCEPTION 'junto.date_in_past';
    END IF;
    IF p_starts_at > NOW() + INTERVAL '6 months' THEN
      RAISE EXCEPTION 'junto.date_too_far';
    END IF;
  END IF;

  -- p_max_participants = 0 is the explicit "make it open" sentinel (NULL
  -- means "unchanged", so it can't express open — the edit screen's open
  -- toggle silently did nothing before this). 0 sits outside the valid
  -- [2,50] range so it can't collide with a real cap. Any other
  -- out-of-range value is rejected (parity with create_activity — before
  -- this it surfaced as a raw table CHECK violation).
  IF p_max_participants IS NOT NULL AND p_max_participants != 0
     AND (p_max_participants < 2 OR p_max_participants > 50) THEN
    RAISE EXCEPTION 'junto.participants_range';
  END IF;

  -- Tamper guard (UI only sends valid values): generic. Parity with create_activity.
  IF p_visibility IS NOT NULL
     AND p_visibility NOT IN ('public', 'approval', 'private_link', 'private_link_approval') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Private-link visibilities open to all (Scott 2026-07-10) — no gate.

  UPDATE activities SET
    title = COALESCE(v_trimmed_title, title),
    description = CASE WHEN p_description IS NOT NULL THEN trim(p_description) ELSE description END,
    level = COALESCE(p_level, level),
    level_max = CASE WHEN p_level IS NOT NULL THEN v_level_max ELSE level_max END,
    max_participants = CASE
      WHEN p_max_participants = 0 THEN NULL
      WHEN p_max_participants IS NOT NULL THEN p_max_participants
      ELSE max_participants END,
    location_meeting = CASE
      WHEN p_meeting_lng IS NOT NULL AND p_meeting_lat IS NOT NULL
      THEN ST_SetSRID(ST_MakePoint(p_meeting_lng, p_meeting_lat), 4326)::geography
      ELSE location_meeting END,
    -- Only alongside a pin move (00441); the trigger freezes it otherwise.
    meeting_locality = CASE
      WHEN p_meeting_lng IS NOT NULL AND p_meeting_lat IS NOT NULL
      THEN CASE WHEN p_meeting_locality IS NOT NULL AND char_length(trim(p_meeting_locality)) > 0
                THEN left(trim(p_meeting_locality), 80) ELSE NULL END
      ELSE meeting_locality END,
    starts_at = COALESCE(p_starts_at, starts_at),
    duration = CASE WHEN p_duration IS NOT NULL THEN p_duration::interval ELSE duration END,
    visibility = COALESCE(p_visibility, visibility)
  WHERE id = p_activity_id;

  -- Re-fetch after the UPDATE (whitelist trigger may have forced privileged
  -- columns back to OLD when participants exist — only notify on real changes).
  SELECT title, description, starts_at, duration, location_meeting,
         max_participants, level, visibility
  INTO v_new FROM activities WHERE id = p_activity_id;

  -- 00489 (AC-8): turning a public / on-request outing private rotates its
  -- link — anyone who saw the old token while it was public loses access.
  IF v_old.visibility IN ('public', 'approval')
     AND v_new.visibility IN ('private_link', 'private_link_approval') THEN
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE activities SET invite_token = gen_random_uuid() WHERE id = p_activity_id;
    PERFORM set_config('junto.bypass_lock', 'false', true);
    DELETE FROM invite_grants WHERE activity_id = p_activity_id;
  END IF;

  v_changes := '{}'::jsonb;
  IF v_old.title IS DISTINCT FROM v_new.title THEN
    v_changes := v_changes || jsonb_build_object('title', true);
  END IF;
  IF v_old.starts_at IS DISTINCT FROM v_new.starts_at THEN
    v_changes := v_changes || jsonb_build_object('starts_at', true);
  END IF;
  IF v_old.duration IS DISTINCT FROM v_new.duration THEN
    v_changes := v_changes || jsonb_build_object('duration', true);
  END IF;
  IF v_old.location_meeting IS DISTINCT FROM v_new.location_meeting THEN
    v_changes := v_changes || jsonb_build_object('location_meeting', true);
  END IF;
  IF v_old.description IS DISTINCT FROM v_new.description THEN
    v_changes := v_changes || jsonb_build_object('description', true);
  END IF;
  IF v_old.level IS DISTINCT FROM v_new.level THEN
    v_changes := v_changes || jsonb_build_object('level', true);
  END IF;
  IF v_old.max_participants IS DISTINCT FROM v_new.max_participants THEN
    v_changes := v_changes || jsonb_build_object('max_participants', true);
  END IF;
  IF v_old.visibility IS DISTINCT FROM v_new.visibility THEN
    v_changes := v_changes || jsonb_build_object('visibility', true);
  END IF;

  -- No real change happened (every requested field was rejected by trigger or unchanged) — skip notif
  IF v_changes = '{}'::jsonb THEN RETURN; END IF;

  FOR v_participant IN
    SELECT user_id FROM participations
    -- 00516 (AC-7): requesters are told too — they must not be accepted
    -- into an outing that changed under them without knowing.
    WHERE activity_id = p_activity_id AND status IN ('accepted', 'pending') AND user_id != v_user_id
  LOOP
    PERFORM create_notification(
      v_participant.user_id,
      'activity_updated',
      'Sortie modifiée',
      '« ' || v_new.title || ' » a changé — vérifie l''heure et le rendez-vous.',
      jsonb_build_object('activity_id', p_activity_id, 'changes', v_changes,
        'params', jsonb_build_object('title', v_new.title))
    );
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.join_activity(p_activity_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_current_count INTEGER;
  v_hourly_count INTEGER;
  v_result_status TEXT;
  v_existing RECORD;
  v_user_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, creator_id, status, visibility, max_participants, title, is_demo, deleted_at
  INTO v_activity
  FROM activities WHERE id = p_activity_id
  FOR UPDATE;

  IF v_activity IS NULL OR v_activity.deleted_at IS NOT NULL
     OR v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00516: once the presence check window of a started outing has passed,
  -- nobody joins any more (they could no longer validate, and could tip a
  -- 2-person outing into the 3+ rule).
  IF EXISTS (SELECT 1 FROM activities a WHERE a.id = p_activity_id AND a.requires_presence
             AND now() > a.starts_at + INTERVAL '15 minutes') THEN
    RAISE EXCEPTION 'junto.activity_locked';
  END IF;

  -- Demo activities are joinable only by an admin currently in demo mode.
  IF v_activity.is_demo AND NOT demo_content_visible() THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id = v_activity.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- 00494 (AC-11): the outing of a suspended organiser is hidden everywhere;
  -- it cannot be joined by id either.
  IF private.user_is_suspended(v_activity.creator_id) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = v_activity.creator_id AND blocked_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00486 (IX-1): a private outing is joined only through its link (opened
  -- by this account) or an invitation from its organiser — never by id alone.
  IF v_activity.visibility IN ('private_link', 'private_link_approval')
     AND NOT private.private_activity_access(p_activity_id, v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT count(*) INTO v_current_count
  FROM participations WHERE activity_id = p_activity_id AND status = 'accepted';
  IF v_current_count >= COALESCE(v_activity.max_participants, 50) THEN
    RAISE EXCEPTION 'junto.activity_full';
  END IF;

  SELECT count(*) INTO v_hourly_count
  FROM participations WHERE user_id = v_user_id AND created_at > NOW() - INTERVAL '1 hour';
  IF v_hourly_count >= 10 THEN RAISE EXCEPTION 'junto.join_rate_limit'; END IF;

  IF v_activity.visibility IN ('public', 'private_link') THEN
    v_result_status := 'accepted';
  ELSE
    v_result_status := 'pending';
  END IF;

  SELECT id, status, refused_at, left_at INTO v_existing
  FROM participations WHERE activity_id = p_activity_id AND user_id = v_user_id;

  -- 00477 (DB-PR-1): test the id, not the record — a RECORD with any NULL field
  -- (refused_at, left_at) is never « IS NOT NULL », which sent every rejoin to
  -- the INSERT branch and a raw unique violation.
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.status = 'removed' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

    IF v_existing.status = 'invited' THEN
      PERFORM set_config('junto.bypass_lock', 'true', true);
      UPDATE participations
      SET status = 'accepted', created_at = now(), left_at = NULL, refused_at = NULL
      WHERE id = v_existing.id;
      SELECT display_name INTO v_user_name FROM public_profiles WHERE id = v_user_id;
      PERFORM create_notification(
        v_activity.creator_id, 'invitation_accepted',
        coalesce(v_user_name, 'Quelqu''un') || ' a accepté ton invitation',
        '« ' || regexp_replace(v_activity.title, '<[^>]*>', '', 'g') || ' »',
        jsonb_build_object('activity_id', p_activity_id,
          'params', jsonb_build_object('name', coalesce(v_user_name, 'Quelqu''un'), 'title', regexp_replace(v_activity.title, '<[^>]*>', '', 'g')))
      );
      RETURN 'accepted';
    END IF;

    IF v_existing.status IN ('accepted', 'pending') THEN RAISE EXCEPTION 'junto.already_joined'; END IF;
    -- 00477 (AB-1): a join/leave loop pushed the organiser without limit — the
    -- hourly cap counts rows and a rejoin reuses the same row. 15 min after a
    -- withdrawal before rejoining the same outing.
    IF v_existing.status = 'withdrawn'
       AND v_existing.left_at IS NOT NULL
       AND v_existing.left_at > NOW() - INTERVAL '15 minutes' THEN
      RAISE EXCEPTION 'junto.rejoin_cooldown';
    END IF;
    IF v_existing.status = 'refused'
       AND v_existing.refused_at IS NOT NULL
       AND v_existing.refused_at > NOW() - INTERVAL '24 hours' THEN
      RAISE EXCEPTION 'junto.refuse_cooldown';
    END IF;

    IF v_result_status = 'accepted' THEN
      SELECT count(*) INTO v_current_count
      FROM participations WHERE activity_id = p_activity_id AND status = 'accepted';
      IF v_current_count >= COALESCE(v_activity.max_participants, 50) THEN
        RAISE EXCEPTION 'junto.activity_full';
      END IF;
    END IF;

    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE participations
    SET status = v_result_status, left_at = NULL, created_at = now(), refused_at = NULL
    WHERE id = v_existing.id;
  ELSE
    IF v_result_status = 'accepted' THEN
      SELECT count(*) INTO v_current_count
      FROM participations WHERE activity_id = p_activity_id AND status = 'accepted';
      IF v_current_count >= COALESCE(v_activity.max_participants, 50) THEN
        RAISE EXCEPTION 'junto.activity_full';
      END IF;
    END IF;

    INSERT INTO participations (activity_id, user_id, status, created_at)
    VALUES (p_activity_id, v_user_id, v_result_status, now());
  END IF;

  SELECT display_name INTO v_user_name FROM public_profiles WHERE id = v_user_id;

  IF v_result_status = 'pending' THEN
    PERFORM create_notification(
      v_activity.creator_id, 'join_request',
      coalesce(v_user_name, 'Quelqu''un') || ' veut rejoindre ta sortie',
      '« ' || v_activity.title || ' »',
      jsonb_build_object('activity_id', p_activity_id,
        'params', jsonb_build_object('name', coalesce(v_user_name, 'Quelqu''un'), 'title', v_activity.title))
    );
  ELSE
    PERFORM notify_participant_joined(v_activity.creator_id, p_activity_id, v_user_name, v_activity.title);
  END IF;

  RETURN v_result_status;
END;
$function$;

CREATE OR REPLACE FUNCTION public.accept_activity_invitation(p_activity_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_row RECORD;
  v_count INTEGER;
  v_updated INTEGER;
  v_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id, creator_id, status, deleted_at, max_participants, title INTO v_activity
  FROM activities WHERE id = p_activity_id
  FOR UPDATE;
  IF v_activity.id IS NULL OR v_activity.deleted_at IS NOT NULL
     OR v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- 00516: once the presence check window of a started outing has passed,
  -- nobody joins any more (they could no longer validate, and could tip a
  -- 2-person outing into the 3+ rule).
  IF EXISTS (SELECT 1 FROM activities a WHERE a.id = p_activity_id AND a.requires_presence
             AND now() > a.starts_at + INTERVAL '15 minutes') THEN
    RAISE EXCEPTION 'junto.activity_locked';
  END IF;
  -- 00496 (AC-11 / BR-4): not a suspended or blocking organiser's outing,
  -- and only from an onboarded account (accepting is an action).
  IF private.user_is_suspended(v_activity.creator_id)
     OR EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = v_activity.creator_id AND blocked_id = v_user_id)
     OR NOT EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.age_confirmed_at IS NOT NULL AND u.accepted_tos_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT id INTO v_row FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'invited';
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT count(*) INTO v_count FROM participations
  WHERE activity_id = p_activity_id AND status = 'accepted';
  IF v_count >= COALESCE(v_activity.max_participants, 50) THEN
    RAISE EXCEPTION 'junto.activity_full';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET status = 'accepted', created_at = now(), left_at = NULL, refused_at = NULL
  WHERE id = v_row.id AND status = 'invited';
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  -- Row vanished between the SELECT and the UPDATE (concurrent decline / block
  -- cascade, which don't take the activity lock) → no phantom success/push.
  IF v_updated = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT display_name INTO v_name FROM public_profiles WHERE id = v_user_id;
  PERFORM create_notification(
    v_activity.creator_id, 'invitation_accepted',
    coalesce(v_name, 'Quelqu''un') || ' a accepté ton invitation',
    '« ' || regexp_replace(v_activity.title, '<[^>]*>', '', 'g') || ' »',
    jsonb_build_object('activity_id', p_activity_id,
      'params', jsonb_build_object('name', coalesce(v_name, 'Quelqu''un'), 'title', regexp_replace(v_activity.title, '<[^>]*>', '', 'g')))
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_participation_transport(p_activity_id uuid, p_transport_type text, p_transport_seats smallint DEFAULT NULL::smallint, p_transport_from_name text DEFAULT NULL::text, p_transport_departs_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_transport_from_lat double precision DEFAULT NULL::double precision, p_transport_from_lng double precision DEFAULT NULL::double precision)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_starts_at TIMESTAMPTZ;
  v_from_name TEXT;
  v_lat DOUBLE PRECISION;
  v_lng DOUBLE PRECISION;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  PERFORM private.rate_hit('transport', 20, INTERVAL '1 minute');  -- 00516 (L5)

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = p_activity_id
      AND status IN ('published', 'in_progress')
      AND starts_at > NOW() - INTERVAL '15 seconds'
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted'
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF p_transport_type IS NOT NULL
     AND p_transport_type NOT IN ('car', 'public_transport', 'bike', 'on_foot', 'other') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00496 (BR-3): someone seated in another car does not offer seats.
  IF p_transport_type = 'car' AND coalesce(p_transport_seats, 0) > 0
     AND EXISTS (SELECT 1 FROM seat_requests
                 WHERE activity_id = p_activity_id AND requester_id = v_user_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'junto.already_seated';
  END IF;

  IF (p_transport_type IS NULL OR p_transport_type != 'car')
     AND EXISTS (
       SELECT 1 FROM seat_requests
       WHERE activity_id = p_activity_id
         AND driver_id = v_user_id
         AND status = 'accepted'
     ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF p_transport_type != 'car' AND p_transport_seats IS NOT NULL AND p_transport_seats > 0 THEN
    p_transport_seats := NULL;
  END IF;

  IF p_transport_departs_at IS NOT NULL THEN
    SELECT starts_at INTO v_starts_at FROM activities WHERE id = p_activity_id;
    IF p_transport_departs_at < v_starts_at - INTERVAL '12 hours'
       OR p_transport_departs_at > v_starts_at + INTERVAL '6 hours' THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
  END IF;

  v_from_name := CASE
    WHEN p_transport_from_name IS NOT NULL AND char_length(trim(p_transport_from_name)) > 0
    THEN regexp_replace(trim(p_transport_from_name), '<[^>]*>', '', 'g')
    ELSE NULL
  END;

  -- Coords only meaningful with a name; range-validated; cleared with the name
  -- (a free-text departure has a name but no coords).
  IF v_from_name IS NULL THEN
    v_lat := NULL; v_lng := NULL;
  ELSE
    IF p_transport_from_lat IS NOT NULL AND p_transport_from_lat NOT BETWEEN -90 AND 90 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    IF p_transport_from_lng IS NOT NULL AND p_transport_from_lng NOT BETWEEN -180 AND 180 THEN
      RAISE EXCEPTION 'Operation not permitted';
    END IF;
    v_lat := p_transport_from_lat; v_lng := p_transport_from_lng;
  END IF;

  UPDATE participations
  SET transport_type = p_transport_type,
      transport_seats = p_transport_seats,
      transport_from_name = v_from_name,
      transport_departs_at = p_transport_departs_at,
      transport_from_lat = v_lat,
      transport_from_lng = v_lng
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';
END;
$function$;

CREATE OR REPLACE FUNCTION public.waive_late_cancel_penalty(p_participation_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_target UUID;
  v_activity UUID;
  v_creator UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users u0 WHERE u0.id = v_user_id AND u0.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  PERFORM private.rate_hit('waive', 20, INTERVAL '1 minute');  -- 00516 (L5)

  SELECT p.user_id, p.activity_id, a.creator_id INTO v_target, v_activity, v_creator
  FROM participations p JOIN activities a ON a.id = p.activity_id
  WHERE p.id = p_participation_id;
  IF NOT FOUND OR v_user_id IS DISTINCT FROM v_creator THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 00478: keyed on the ledger, so a waiver still works after the person rejoined.
  IF NOT EXISTS (SELECT 1 FROM late_cancels WHERE user_id = v_target AND activity_id = v_activity) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE late_cancels SET waived = TRUE WHERE user_id = v_target AND activity_id = v_activity;
  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations SET penalty_waived = TRUE WHERE id = p_participation_id;
  PERFORM set_config('junto.bypass_lock', 'false', true);

  PERFORM recalculate_reliability_score(v_target);
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
  -- 00516 (DX-3): a suspended account reveals nothing.
  IF private.user_is_suspended(p_user_id) THEN RETURN; END IF;
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

CREATE OR REPLACE FUNCTION public.get_user_reputation(p_user_id uuid)
 RETURNS TABLE(badge_key text, vote_count integer, last_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller UUID;
  v_negative_keys TEXT[] := ARRAY[
    'unprepared', 'aggressive', 'reckless',
    'late_canceller', 'level_overestimated', 'unreliable_field', 'difficult_attitude'
  ];
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_caller AND suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  -- 00419 M3 : rideau démo.
  -- 00516 (DX-3): a suspended account reveals nothing.
  IF private.user_is_suspended(p_user_id) THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users du WHERE du.id = p_user_id AND du.is_demo = true)
     AND NOT demo_content_visible() THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH grouped AS (
    SELECT
      rv.badge_key,
      count(DISTINCT rv.voter_id)::int AS total_count,  -- 00496 (PR-11): people, not votes
      date_trunc('month', max(rv.created_at)) AS max_at  -- 00496 (PR-3): no exact vote time
    FROM reputation_votes rv
    WHERE rv.voted_id = p_user_id
      AND rv.counted_at IS NOT NULL
      AND rv.badge_key NOT IN ('level_over', 'level_right', 'level_under')
    GROUP BY rv.badge_key
  )
  SELECT
    g.badge_key,
    CASE
      WHEN g.badge_key = ANY(v_negative_keys)
        THEN get_active_negative_count(p_user_id, g.badge_key)
      ELSE g.total_count
    END AS vote_count,
    g.max_at AS last_at
  FROM grouped g
  WHERE
    -- 00496 (PR-3): a negative trait is returned only from the warning
    -- threshold the app shows (5) — below it, even its target cannot tell
    -- who voted by elimination.
    NOT (
      g.badge_key = ANY(v_negative_keys)
      AND get_active_negative_count(p_user_id, g.badge_key) < 5
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_voters_for_badge(p_user_id uuid, p_badge_key text)
 RETURNS TABLE(voter_id uuid, display_name text, avatar_url text, voted_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  -- 00493 (IX-3): demo curtain, like get_user_reputation.
  -- 00516 (DX-3): a suspended account reveals nothing.
  IF private.user_is_suspended(p_user_id) THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users du WHERE du.id = p_user_id AND du.is_demo = true)
     AND NOT demo_content_visible() THEN
    RETURN;
  END IF;
  -- 00493 (PR-3): voters are shown only for a POSITIVE trait, and only once
  -- at least 5 different people gave it (the app shows the trait from 5 on).
  -- A negative vote never reveals its author (no retaliation).
  IF p_badge_key NOT IN ('punctual', 'prepared', 'conciliant', 'prudent') THEN RETURN; END IF;
  IF (SELECT count(DISTINCT rv.voter_id) FROM reputation_votes rv
      WHERE rv.voted_id = p_user_id AND rv.badge_key = p_badge_key AND rv.counted_at IS NOT NULL) < 5 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT *
  FROM (
    SELECT DISTINCT ON (rv.voter_id)
      pp.id           AS voter_id,
      pp.display_name AS display_name,
      pp.avatar_url   AS avatar_url,
      date_trunc('month', rv.created_at) AS voted_at  -- 00516 (PR-3)
    FROM reputation_votes rv
    JOIN public_profiles pp ON pp.id = rv.voter_id
    WHERE rv.voted_id  = p_user_id
      AND rv.badge_key = p_badge_key
      AND rv.counted_at IS NOT NULL
    ORDER BY rv.voter_id, rv.created_at DESC
  ) deduped
  ORDER BY deduped.voted_at DESC;
END;
$function$;
