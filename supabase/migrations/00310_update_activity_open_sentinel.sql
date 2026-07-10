-- 00310: update_activity — explicit "open activity" sentinel
--
-- The edit screen's open toggle sent p_max_participants = NULL, which the
-- function reads as "unchanged" (COALESCE) — switching a capped activity to
-- open silently did nothing while the UI toasted success. NULL can't carry
-- both meanings, so 0 (outside the valid [2,50] range) is the explicit
-- "make it open" sentinel, mapped to NULL in the UPDATE. Also adds the
-- junto.participants_range check (parity with create_activity; other
-- out-of-range values previously died as a raw table CHECK violation).
-- Signature unchanged -> CREATE OR REPLACE, grants preserved. The
-- participant-lock trigger still forces max_participants back to OLD when
-- accepted participants exist. Everything else is byte-identical to 00309.

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
  p_level_max TEXT DEFAULT NULL
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
  v_tier TEXT;
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

  -- Premium gate on SWITCHING to a private-link visibility (parity with
  -- create_activity). No-op resends of an already-private visibility pass —
  -- a creator whose tier lapsed keeps what they have but can't gate more.
  IF p_visibility IN ('private_link', 'private_link_approval')
     AND p_visibility IS DISTINCT FROM v_old.visibility THEN
    SELECT tier INTO v_tier FROM users WHERE id = v_user_id;
    IF v_tier NOT IN ('premium', 'pro') THEN
      RAISE EXCEPTION 'junto.premium_required';
    END IF;
  END IF;

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
      'Activité modifiée',
      v_new.title || ' a été modifiée',
      jsonb_build_object('activity_id', p_activity_id, 'changes', v_changes)
    );
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION update_activity FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION update_activity FROM anon;
GRANT EXECUTE ON FUNCTION update_activity TO authenticated;
