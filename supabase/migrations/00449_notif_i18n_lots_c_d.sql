-- ============================================================================
-- 00449 — Notifications multilingues, lots C (participation, sortie) et D
-- (covoiturage). Même principe que 00447/00448 : title/body FR = secours,
-- data.params (+ variant) pour la langue du lecteur. Copy FR alignée sur
-- l'audit : « Tu es dans la sortie ! », « Tu ne fais plus partie de la
-- sortie », « Sortie annulée / modifiée », « Nouvelle sortie pour ton alerte »,
-- « Pas de place » (covoit), départ tardif explicite, guillemets partout.
-- Rituel live-version : chaque fonction reconstruite depuis sa dernière
-- définition ; seuls les appels de notification changent ; grants conservés.
--   accept_participation         ← 00312
--   refuse_participation         ← 00116
--   notify_participant_joined    ← 00117
--   leave_activity               ← 00116
--   remove_participant           ← 00430
--   cancel_activity              ← 00269
--   update_activity              ← 00441
--   check_alerts_for_activity    ← 00306
--   request_seat                 ← 00419
--   accept_seat_request          ← 00419
--   decline_seat_request         ← 00235
--   expire_idle_seat_requests    ← 00302
-- ============================================================================

-- ---------- accept_participation (base 00312) ----------
CREATE OR REPLACE FUNCTION accept_participation(
  p_participation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
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
$$;

-- ---------- refuse_participation (base 00116) ----------
CREATE OR REPLACE FUNCTION refuse_participation(
  p_participation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
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
$$;

-- ---------- notify_participant_joined (base 00117) ----------
CREATE OR REPLACE FUNCTION notify_participant_joined(
  p_creator_id UUID,
  p_activity_id UUID,
  p_joiner_name TEXT,
  p_activity_title TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_existing RECORD;
  v_count INTEGER;
  v_recent_names JSONB;
  v_clean_name TEXT;
  v_clean_title TEXT;
  v_body TEXT;
  v_secret TEXT;
  v_names_arr TEXT[];
BEGIN
  v_clean_name := sanitize_notif_text(coalesce(p_joiner_name, 'Quelqu''un'));
  v_clean_title := sanitize_notif_text(coalesce(p_activity_title, ''));

  SELECT id, data INTO v_existing
  FROM notifications
  WHERE user_id = p_creator_id
    AND type = 'participant_joined'
    AND (data->>'activity_id')::uuid = p_activity_id
    AND read_at IS NULL
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_existing IS NULL THEN
    PERFORM create_notification(
      p_creator_id,
      'participant_joined',
      'Nouveau participant',
      v_clean_name || ' a rejoint « ' || v_clean_title || ' »',
      jsonb_build_object(
        'activity_id', p_activity_id,
        'count', 1,
        'recent_names', jsonb_build_array(v_clean_name),
        'params', jsonb_build_object('name', v_clean_name, 'title', v_clean_title)
      )
    );
    RETURN;
  END IF;

  v_count := COALESCE((v_existing.data->>'count')::int, 1) + 1;
  v_recent_names := COALESCE(v_existing.data->'recent_names', '[]'::jsonb)
                    || jsonb_build_array(v_clean_name);
  -- Keep at most last 3 names
  IF jsonb_array_length(v_recent_names) > 3 THEN
    v_recent_names := jsonb_path_query_array(v_recent_names, '$[1 to last]');
  END IF;

  SELECT array_agg(value) INTO v_names_arr
  FROM jsonb_array_elements_text(v_recent_names) WITH ORDINALITY;

  IF v_count = 2 THEN
    v_body := v_names_arr[1] || ' et ' || v_names_arr[2] || ' ont rejoint ' || v_clean_title;
  ELSE
    v_body := v_names_arr[array_upper(v_names_arr, 1)]
              || ' et ' || (v_count - 1)::text || ' autres ont rejoint ' || v_clean_title;
  END IF;

  UPDATE notifications
  SET body = v_body,
      data = jsonb_set(
        jsonb_set(v_existing.data, '{count}', to_jsonb(v_count)),
        '{recent_names}', v_recent_names
      ),
      created_at = now(),
      read_at = NULL
  WHERE id = v_existing.id;

  -- AFTER INSERT trigger doesn't fire on UPDATE, so push manually with collapseId
  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';
  IF v_secret IS NOT NULL THEN
    PERFORM net.http_post(
      url := 'https://lvjlthzdydzatcvwwriu.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-junto-push-secret', v_secret
      ),
      body := jsonb_build_object(
        'user_id', p_creator_id,
        'title', 'Nouveau participant',
        'body', v_body,
        'data', jsonb_build_object(
          'activity_id', p_activity_id,
          'count', v_count,
          'type', 'participant_joined'
        ),
        'collapseId', 'joined-' || p_activity_id::text
      )
    );
  END IF;
END;
$$;

-- ---------- leave_activity (base 00116) ----------
CREATE OR REPLACE FUNCTION leave_activity(
  p_activity_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
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

  SELECT p.id, p.status, p.transport_type, p.transport_seats
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

  v_is_late := v_activity.requires_presence
               AND (v_activity.starts_at - INTERVAL '12 hours' < now());

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

  PERFORM recalculate_reliability_score(v_user_id);

  SELECT display_name INTO v_user_name FROM users WHERE id = v_user_id;
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
$$;

-- ---------- remove_participant (base 00430) ----------
CREATE OR REPLACE FUNCTION remove_participant(
  p_participation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_participation RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT p.id, p.user_id, p.status, p.activity_id, p.confirmed_present,
         a.creator_id, a.title, a.status AS activity_status, a.deleted_at
  INTO v_participation
  FROM participations p
  JOIN activities a ON a.id = p.activity_id
  WHERE p.id = p_participation_id
  FOR UPDATE OF p;

  IF v_participation IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_participation.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_participation.user_id = v_participation.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_participation.status != 'accepted' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_participation.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- 00430 : retirer quelqu'un est une action de LOGISTIQUE (avant / pendant),
  -- pas une édition d'historique. Après la fin, la liste des participants est
  -- un fait acquis. Code parlant : le créateur voit que la sortie est passée,
  -- rien de sensible n'est révélé.
  IF v_participation.activity_status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'junto.activity_ended_no_remove';
  END IF;

  -- 00430 : on ne « dés-invite » pas quelqu'un dont la présence est VÉRIFIÉE
  -- (QR, géo ou témoignage de deux pairs). Avant, cette présence était effacée
  -- (`confirmed_present = NULL`) : la victime perdait son crédit de fiabilité
  -- et sa sortie réelle, et à 3+ retirer le seul confirmé neutralisait tout le
  -- monde. On refuse plutôt que d'effacer le fait.
  IF v_participation.confirmed_present IS NOT NULL THEN
    RAISE EXCEPTION 'junto.participant_present_no_remove';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE participations
  SET status = 'removed',
      confirmed_present = NULL   -- déjà NULL (gardé par ceinture)
  WHERE id = p_participation_id;
  PERFORM set_config('junto.bypass_lock', 'false', true);

  PERFORM create_notification(
    v_participation.user_id,
    'participant_removed',
    'Tu ne fais plus partie de la sortie',
    '« ' || v_participation.title || ' »',
    jsonb_build_object('activity_id', v_participation.activity_id,
      'params', jsonb_build_object('title', v_participation.title))
  );
END;
$$;

-- ---------- cancel_activity (base 00269) ----------
CREATE OR REPLACE FUNCTION cancel_activity(
  p_activity_id UUID,
  p_reason TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
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

  v_clean_reason := NULLIF(trim(coalesce(p_reason, '')), '');
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
$$;

-- ---------- update_activity (base 00441) ----------
CREATE OR REPLACE FUNCTION update_activity(
  p_activity_id UUID,
  p_title TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_level TEXT DEFAULT NULL,
  p_max_participants INTEGER DEFAULT NULL,
  p_meeting_lng FLOAT DEFAULT NULL,
  p_meeting_lat FLOAT DEFAULT NULL,
  p_starts_at TIMESTAMPTZ DEFAULT NULL,
  p_duration TEXT DEFAULT NULL,
  p_visibility TEXT DEFAULT NULL,
  p_level_max TEXT DEFAULT NULL,
  p_meeting_locality TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
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

  IF p_title IS NOT NULL THEN
    v_trimmed_title := trim(p_title);
    IF char_length(v_trimmed_title) < 3 THEN RAISE EXCEPTION 'junto.title_too_short'; END IF;
  END IF;

  -- Normalised range high end (only applied when the level is being edited).
  v_level_max := NULLIF(trim(coalesce(p_level_max, '')), '');
  IF p_level IS NOT NULL AND v_level_max = trim(p_level) THEN v_level_max := NULL; END IF;

  SELECT id, creator_id, status, title, description, starts_at, duration,
         location_meeting, max_participants, level, visibility
  INTO v_old FROM activities WHERE id = p_activity_id FOR UPDATE;

  IF v_old IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_old.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_old.status NOT IN ('published', 'in_progress') THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

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
    WHERE activity_id = p_activity_id AND status = 'accepted' AND user_id != v_user_id
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
$$;

-- ---------- check_alerts_for_activity (base 00306) ----------
CREATE OR REPLACE FUNCTION check_alerts_for_activity(
  p_activity_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_activity RECORD;
  v_sport_key TEXT;
  v_activity_date DATE;
  v_alert RECORD;
  v_today_count INTEGER;
BEGIN
  SELECT a.id, a.creator_id, a.title, a.location_meeting,
         a.starts_at, a.level, a.status, a.deleted_at, s.key AS sport_key
  INTO v_activity
  FROM activities a JOIN sports s ON s.id = a.sport_id
  WHERE a.id = p_activity_id;

  IF v_activity IS NULL OR v_activity.status != 'published' OR v_activity.deleted_at IS NOT NULL THEN
    RETURN;
  END IF;

  v_sport_key := v_activity.sport_key;
  v_activity_date := v_activity.starts_at::date;

  FOR v_alert IN
    SELECT a.id, a.user_id
    FROM activity_alerts a
    WHERE a.user_id != v_activity.creator_id
      AND (a.sport_key IS NULL OR a.sport_key = v_sport_key)
      AND (a.levels IS NULL OR v_activity.level = ANY(a.levels))
      AND (a.starts_on IS NULL OR v_activity_date >= a.starts_on)
      AND (a.ends_on IS NULL OR v_activity_date <= a.ends_on)
      AND NOT EXISTS (
        SELECT 1 FROM blocked_users b
        WHERE (b.blocker_id = v_activity.creator_id AND b.blocked_id = a.user_id)
           OR (b.blocker_id = a.user_id AND b.blocked_id = v_activity.creator_id)
      )
      AND ST_DWithin(a.location, v_activity.location_meeting, a.radius_km * 1000)
  LOOP
    -- Per-user advisory lock so the count+insert is atomic vs. concurrent
    -- alert checks for the same user (multiple activities published in parallel).
    PERFORM pg_advisory_xact_lock(hashtext('alert_match_' || v_alert.user_id::text));

    SELECT count(*) INTO v_today_count
    FROM notifications
    WHERE user_id = v_alert.user_id
      AND type = 'alert_match'
      AND created_at >= date_trunc('day', now() AT TIME ZONE 'UTC');

    IF v_today_count >= 3 THEN CONTINUE; END IF;

    PERFORM create_notification(
      v_alert.user_id,
      'alert_match',
      'Nouvelle sortie pour ton alerte',
      '« ' || v_activity.title || ' »',
      jsonb_build_object('activity_id', p_activity_id,
        'params', jsonb_build_object('title', v_activity.title))
    );
  END LOOP;
END;
$$;

-- ---------- request_seat (base 00419) ----------
CREATE OR REPLACE FUNCTION request_seat(
  p_activity_id UUID,
  p_driver_id UUID,
  p_pickup_from TEXT DEFAULT NULL,
  p_message TEXT DEFAULT NULL,
  p_requested_pickup_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_request_id UUID;
  v_requester_name TEXT;
  v_activity_title TEXT;
  v_starts_at TIMESTAMPTZ;
  v_existing RECORD;
  v_pickup TEXT;
  v_message TEXT;
  v_conversation_id UUID;
  v_conv_status TEXT;
  v_u1 UUID;
  v_u2 UUID;
  v_seed_message TEXT;
  v_recent_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_driver_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = p_driver_id)
       OR (blocker_id = p_driver_id AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('request_seat:' || v_user_id::text));

  SELECT count(*) INTO v_recent_count
  FROM seat_requests
  WHERE requester_id = v_user_id
    AND created_at > NOW() - INTERVAL '5 minutes';
  IF v_recent_count >= 5 THEN RAISE EXCEPTION 'junto.seat_rate_limit'; END IF;

  IF NOT EXISTS (SELECT 1 FROM participations WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM participations WHERE activity_id = p_activity_id AND user_id = p_driver_id AND status = 'accepted') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT a.starts_at, a.title INTO v_starts_at, v_activity_title
  FROM activities a
  WHERE a.id = p_activity_id
    AND a.status IN ('published', 'in_progress')
    AND a.starts_at > NOW() - INTERVAL '15 seconds'
    AND a.deleted_at IS NULL;
  IF v_starts_at IS NULL THEN RAISE EXCEPTION 'junto.activity_locked'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM participations
    WHERE activity_id = p_activity_id AND user_id = p_driver_id
      AND transport_type IN ('car', 'carpool') AND transport_seats > 0
  ) THEN RAISE EXCEPTION 'junto.no_seats_available'; END IF;

  IF p_requested_pickup_at IS NOT NULL THEN
    IF p_requested_pickup_at < v_starts_at - INTERVAL '12 hours'
       OR p_requested_pickup_at > v_starts_at + INTERVAL '6 hours' THEN
      RAISE EXCEPTION 'junto.pickup_out_of_window';
    END IF;
  END IF;

  -- Strip HTML/script tags from pickup_from too (message already does).
  v_pickup := CASE
    WHEN p_pickup_from IS NOT NULL AND char_length(trim(p_pickup_from)) > 0
    THEN regexp_replace(trim(p_pickup_from), '<[^>]*>', '', 'g')
    ELSE NULL
  END;
  v_message := CASE WHEN p_message IS NOT NULL AND char_length(trim(p_message)) > 0
                    THEN regexp_replace(trim(p_message), '<[^>]*>', '', 'g') ELSE NULL END;

  SELECT * INTO v_existing
  FROM seat_requests
  WHERE activity_id = p_activity_id AND requester_id = v_user_id AND driver_id = p_driver_id
  FOR UPDATE;

  IF v_existing IS NOT NULL THEN
    IF v_existing.status = 'pending' THEN RAISE EXCEPTION 'junto.seat_already_requested'; END IF;
    IF v_existing.status = 'accepted' THEN RAISE EXCEPTION 'junto.seat_already_requested'; END IF;
    UPDATE seat_requests
    SET status = 'pending', created_at = NOW(),
        pickup_from = v_pickup, message = v_message,
        requested_pickup_at = p_requested_pickup_at
    WHERE id = v_existing.id;
    v_request_id := v_existing.id;
  ELSE
    BEGIN
      INSERT INTO seat_requests (activity_id, requester_id, driver_id, pickup_from, message, requested_pickup_at)
      VALUES (p_activity_id, v_user_id, p_driver_id, v_pickup, v_message, p_requested_pickup_at)
      RETURNING id INTO v_request_id;
    EXCEPTION WHEN unique_violation THEN
      RAISE EXCEPTION 'Operation not permitted';
    END;
  END IF;

  IF v_user_id < p_driver_id THEN
    v_u1 := v_user_id; v_u2 := p_driver_id;
  ELSE
    v_u1 := p_driver_id; v_u2 := v_user_id;
  END IF;

  -- 00419 M2 : réutiliser TOUTE ligne DM de la paire (pas seulement active).
  -- Une ligne pending/declined est réactivée en logistique (retag 'transport'
  -- + purge des champs de requête — invariant 00372 : un refus social ne
  -- devient pas un contact par le covoit). Plus d'unique_violation brute.
  SELECT id, status INTO v_conversation_id, v_conv_status
  FROM conversations
  WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2
  FOR UPDATE;

  IF v_conversation_id IS NULL THEN
    BEGIN
      INSERT INTO conversations (user_1, user_2, initiated_by, status, initiated_from, created_at, last_message_at)
      VALUES (v_u1, v_u2, v_user_id, 'active', 'transport', NOW(), NOW())
      RETURNING id INTO v_conversation_id;
    EXCEPTION WHEN unique_violation THEN
      SELECT id INTO v_conversation_id FROM conversations
      WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2;
    END;
  ELSIF v_conv_status != 'active' THEN
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE conversations
    SET status = 'active', initiated_from = 'transport',
        request_sender_id = NULL, request_message = NULL,
        pending_activity_id = NULL, request_expires_at = NULL,
        last_message_at = NOW()
    WHERE id = v_conversation_id;
    UPDATE conversation_members SET hidden_at = NULL
    WHERE conversation_id = v_conversation_id AND hidden_at IS NOT NULL;
    PERFORM set_config('junto.bypass_lock', 'false', true);
  END IF;

  v_seed_message := '🚗 Demande de place pour « ' || v_activity_title || ' »'
    || CASE WHEN v_pickup IS NOT NULL THEN E'\nDepuis : ' || v_pickup ELSE '' END
    || CASE WHEN v_message IS NOT NULL THEN E'\n\n' || v_message ELSE '' END;

  INSERT INTO private_messages (conversation_id, sender_id, receiver_id, content, metadata, created_at)
  VALUES (
    v_conversation_id, v_user_id, p_driver_id, v_seed_message,
    jsonb_build_object(
      'type', 'seat_request_pending',
      'activity_id', p_activity_id,
      'seat_request_id', v_request_id
    ),
    NOW()
  );

  UPDATE conversations SET last_message_at = NOW() WHERE id = v_conversation_id;

  SELECT display_name INTO v_requester_name FROM public_profiles WHERE id = v_user_id;

  PERFORM create_notification(
    p_driver_id,
    'seat_request',
    'Demande de covoiturage',
    coalesce(v_requester_name, 'Quelqu''un') || ' demande une place pour « ' || v_activity_title || ' »'
      || CASE WHEN v_pickup IS NOT NULL THEN ' depuis ' || v_pickup ELSE '' END,
    jsonb_build_object(
      'seat_request_id', v_request_id,
      'activity_id', p_activity_id,
      'from_user_id', v_user_id,
      'conversation_id', v_conversation_id,
      'variant', CASE WHEN v_pickup IS NOT NULL THEN 'pickup' ELSE NULL END,
      'params', jsonb_build_object('name', coalesce(v_requester_name, 'Quelqu''un'), 'title', v_activity_title, 'pickup', coalesce(v_pickup, ''))
    )
  );

  RETURN v_conversation_id;
END;
$$;

-- ---------- accept_seat_request (base 00419) ----------
CREATE OR REPLACE FUNCTION accept_seat_request(p_request_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_req RECORD;
  v_driver_part RECORD;
  v_requester_name TEXT;
  v_driver_name TEXT;
  v_activity_title TEXT;
  v_driver_from TEXT;
  v_conversation_id UUID;
  v_conv_status TEXT;
  v_u1 UUID;
  v_u2 UUID;
  v_message TEXT;
  v_updated_count INTEGER;
  v_skip_seed BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_req FROM seat_requests WHERE id = p_request_id FOR UPDATE;
  IF v_req IS NULL OR v_req.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_req.driver_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = v_req.activity_id
      AND status IN ('published', 'in_progress')
      AND starts_at > NOW() - INTERVAL '15 seconds'
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'junto.activity_locked'; END IF;

  SELECT id, transport_seats, transport_from_name INTO v_driver_part
  FROM participations
  WHERE activity_id = v_req.activity_id AND user_id = v_req.driver_id AND status = 'accepted'
  FOR UPDATE;

  IF v_driver_part IS NULL OR coalesce(v_driver_part.transport_seats, 0) <= 0 THEN
    RAISE EXCEPTION 'junto.seats_exhausted';
  END IF;

  UPDATE seat_requests SET status = 'accepted'
  WHERE id = p_request_id AND status = 'pending';
  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  IF v_updated_count = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  UPDATE participations
  SET transport_seats = GREATEST(0, transport_seats - 1)
  WHERE id = v_driver_part.id;

  UPDATE participations
  SET transport_type = NULL, transport_seats = NULL, transport_from_name = NULL
  WHERE activity_id = v_req.activity_id AND user_id = v_req.requester_id AND status = 'accepted';
  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  IF v_updated_count = 0 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  v_driver_from := v_driver_part.transport_from_name;
  SELECT display_name INTO v_requester_name FROM public_profiles WHERE id = v_req.requester_id;
  SELECT display_name INTO v_driver_name FROM public_profiles WHERE id = v_req.driver_id;
  SELECT title INTO v_activity_title FROM activities WHERE id = v_req.activity_id;

  SELECT EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_req.driver_id AND blocked_id = v_req.requester_id)
       OR (blocker_id = v_req.requester_id AND blocked_id = v_req.driver_id)
  ) OR EXISTS (
    SELECT 1 FROM users u WHERE u.id = v_req.requester_id AND u.suspended_at IS NOT NULL
  ) INTO v_skip_seed;

  IF v_req.requester_id < v_req.driver_id THEN
    v_u1 := v_req.requester_id; v_u2 := v_req.driver_id;
  ELSE
    v_u1 := v_req.driver_id; v_u2 := v_req.requester_id;
  END IF;

  -- 00419 M2 : réutiliser TOUTE ligne DM de la paire (retag 'transport' à la
  -- réactivation, purge des champs de requête). Plus d'unique_violation brute.
  SELECT id, status INTO v_conversation_id, v_conv_status
  FROM conversations
  WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2
  FOR UPDATE;

  IF NOT v_skip_seed THEN
    IF v_conversation_id IS NULL THEN
      BEGIN
        INSERT INTO conversations (user_1, user_2, initiated_by, status, initiated_from, created_at, last_message_at)
        VALUES (v_u1, v_u2, v_req.driver_id, 'active', 'transport', NOW(), NOW())
        RETURNING id INTO v_conversation_id;
      EXCEPTION WHEN unique_violation THEN
        SELECT id INTO v_conversation_id FROM conversations
        WHERE type = 'dm' AND user_1 = v_u1 AND user_2 = v_u2;
      END;
    ELSIF v_conv_status != 'active' THEN
      PERFORM set_config('junto.bypass_lock', 'true', true);
      UPDATE conversations
      SET status = 'active', initiated_from = 'transport',
          request_sender_id = NULL, request_message = NULL,
          pending_activity_id = NULL, request_expires_at = NULL,
          last_message_at = NOW()
      WHERE id = v_conversation_id;
      UPDATE conversation_members SET hidden_at = NULL
      WHERE conversation_id = v_conversation_id AND hidden_at IS NOT NULL;
      PERFORM set_config('junto.bypass_lock', 'false', true);
    END IF;

    v_message := '🚗 Place réservée pour « ' || v_activity_title || ' »'
      || CASE WHEN v_req.pickup_from IS NOT NULL THEN ' — pickup depuis ' || v_req.pickup_from ELSE '' END
      || CASE WHEN v_driver_from IS NOT NULL THEN ' (départ ' || v_driver_from || ')' ELSE '' END;

    INSERT INTO private_messages (conversation_id, sender_id, receiver_id, content, metadata, created_at)
    VALUES (
      v_conversation_id, v_req.driver_id, v_req.requester_id, v_message,
      jsonb_build_object('type', 'seat_accepted', 'activity_id', v_req.activity_id),
      NOW()
    );

    UPDATE conversations SET last_message_at = NOW() WHERE id = v_conversation_id;
  ELSIF v_conv_status IS DISTINCT FROM 'active' THEN
    -- Seed sauté (blocage/suspension) : ne pas pointer la notif vers un fil
    -- non actif.
    v_conversation_id := NULL;
  END IF;

  PERFORM create_notification(
    v_req.requester_id,
    'seat_request_accepted',
    'Place confirmée !',
    coalesce(v_driver_name, 'Le conducteur') || ' a accepté ta demande pour « ' || v_activity_title || ' »',
    jsonb_build_object(
      'activity_id', v_req.activity_id,
      'driver_id', v_req.driver_id,
      'conversation_id', v_conversation_id,
      'params', jsonb_build_object('name', coalesce(v_driver_name, 'Le conducteur'), 'title', v_activity_title)
    )
  );

  RETURN v_conversation_id;
END;
$$;

-- ---------- decline_seat_request (base 00235) ----------
CREATE OR REPLACE FUNCTION decline_seat_request(
  p_request_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_req RECORD;
  v_driver_name TEXT;
  v_activity_title TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_req FROM seat_requests WHERE id = p_request_id FOR UPDATE;
  IF v_req IS NULL OR v_req.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_req.driver_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = v_req.activity_id
      AND status IN ('published', 'in_progress')
      AND starts_at > NOW() - INTERVAL '15 seconds'
      AND deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  UPDATE seat_requests SET status = 'declined' WHERE id = p_request_id;

  SELECT display_name INTO v_driver_name FROM public_profiles WHERE id = v_req.driver_id;
  SELECT title INTO v_activity_title FROM activities WHERE id = v_req.activity_id;

  PERFORM create_notification(
    v_req.requester_id,
    'seat_request_declined',
    'Pas de place',
    coalesce(v_driver_name, 'Le conducteur') || ' a refusé ta demande pour « ' || v_activity_title || ' »',
    jsonb_build_object(
      'seat_request_id', v_req.id,
      'activity_id', v_req.activity_id,
      'driver_id', v_req.driver_id,
      'params', jsonb_build_object('name', coalesce(v_driver_name, 'Le conducteur'), 'title', v_activity_title)
    )
  );
END;
$$;

-- ---------- expire_idle_seat_requests (base 00302) ----------
CREATE OR REPLACE FUNCTION expire_idle_seat_requests()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request RECORD;
  v_activity_title TEXT;
BEGIN
  FOR v_request IN
    SELECT sr.id, sr.requester_id, sr.activity_id
    FROM seat_requests sr
    JOIN activities a ON a.id = sr.activity_id
    WHERE sr.status = 'pending'
      AND sr.created_at < NOW() - INTERVAL '48 hours'
      AND a.status IN ('published', 'in_progress')
      AND a.deleted_at IS NULL
    FOR UPDATE OF sr
  LOOP
    UPDATE seat_requests SET status = 'expired'
    WHERE id = v_request.id AND status = 'pending';

    SELECT title INTO v_activity_title FROM activities WHERE id = v_request.activity_id;

    PERFORM create_notification(
      v_request.requester_id,
      'seat_request_expired',
      'Demande sans réponse',
      'Ta demande de covoiturage pour « ' || coalesce(v_activity_title, '?') || ' » a expiré sans réponse du conducteur.',
      jsonb_build_object('activity_id', v_request.activity_id, 'seat_request_id', v_request.id,
        'params', jsonb_build_object('title', coalesce(v_activity_title, '?')))
    );
  END LOOP;
END;
$$;
