-- Migration 00291: presence model — creator auto-validation on geo, no
-- self-validate nags to the creator, and the 2-person rule (Scott 2026-07-07).
--
-- Rules validated with Scott:
--   A. Creator auto-validates when ANY non-creator confirms (QR already did
--      this; geo now does too).
--   B. The creator is never nagged to "validate your presence" — their
--      presence comes from others / the auto-flip.
--   C. A 2-person activity has NO trustworthy peer testimony (mutual vouching
--      is circular), so presence there is ONLY via QR/geo. If no non-creator
--      confirmed via QR/geo by finalisation (T+duration+24h), the activity is
--      re-expired with NO penalty for anyone (like the solo case), and any lone
--      self-validation is wiped so it counts for nobody. 3+ activities keep the
--      full peer-testimony flow.
--
-- Validation window unchanged (T-15min .. T+duration+3h; the 3h serves the
-- offline outdoor replay). Finalisation unchanged (T+duration+24h).
--
-- Each function reproduced VERBATIM from its live definition; only the targeted
-- rule changes applied. ROLLBACK: scratchpad 00291_rollback.sql.

-- ============================================================================
-- A. confirm_presence_via_geo — auto-flip the creator when a non-creator
--    confirms by geo (mirrors confirm_presence_via_token).
-- ============================================================================
CREATE OR REPLACE FUNCTION public.confirm_presence_via_geo(
  p_activity_id uuid, p_lng double precision, p_lat double precision,
  p_captured_at timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_skip_push boolean DEFAULT true)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_user_id UUID;
  v_user_point GEOGRAPHY;
  v_d_start FLOAT;
  v_d_meeting FLOAT;
  v_d_end FLOAT;
  v_d_trace FLOAT;
  v_min_distance FLOAT;
  v_participation_id UUID;
  v_already_confirmed BOOLEAN;
  v_starts_at TIMESTAMPTZ;
  v_duration INTERVAL;
  v_status TEXT;
  v_deleted_at TIMESTAMPTZ;
  v_window_anchor TIMESTAMPTZ;
  v_creator_id UUID;
  v_creator_flipped INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT starts_at, duration, status, deleted_at, creator_id
  INTO v_starts_at, v_duration, v_status, v_deleted_at, v_creator_id
  FROM activities WHERE id = p_activity_id;
  IF v_starts_at IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF v_deleted_at IS NOT NULL THEN RAISE EXCEPTION 'junto.presence_unavailable'; END IF;
  IF v_status NOT IN ('published', 'in_progress', 'completed') THEN
    RAISE EXCEPTION 'junto.presence_unavailable';
  END IF;

  IF p_captured_at IS NULL THEN
    v_window_anchor := now();
  ELSE
    IF now() > v_starts_at + v_duration + INTERVAL '3 hours' THEN
      RAISE EXCEPTION 'junto.presence_window_closed';
    END IF;
    v_window_anchor := p_captured_at;
  END IF;

  IF v_window_anchor < v_starts_at - INTERVAL '15 minutes'
     OR v_window_anchor > v_starts_at + INTERVAL '15 minutes' THEN
    RAISE EXCEPTION 'junto.presence_window_closed';
  END IF;

  SELECT id, confirmed_present IS NOT NULL
  INTO v_participation_id, v_already_confirmed
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';

  IF v_participation_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_already_confirmed THEN RETURN; END IF;

  v_user_point := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography;

  SELECT
    ST_Distance(location_start, v_user_point),
    CASE WHEN location_meeting IS NOT NULL THEN ST_Distance(location_meeting, v_user_point) ELSE NULL END,
    CASE WHEN location_end IS NOT NULL THEN ST_Distance(location_end, v_user_point) ELSE NULL END,
    CASE WHEN trace_geojson IS NOT NULL
         THEN ST_Distance(ST_GeomFromGeoJSON(trace_geojson::text)::geography, v_user_point)
         ELSE NULL END
  INTO v_d_start, v_d_meeting, v_d_end, v_d_trace
  FROM activities WHERE id = p_activity_id;

  v_min_distance := LEAST(
    coalesce(v_d_start,   999999),
    coalesce(v_d_meeting, 999999),
    coalesce(v_d_end,     999999),
    coalesce(v_d_trace,   999999)
  );

  IF v_min_distance IS NULL OR v_min_distance > 150 THEN
    RAISE EXCEPTION 'junto.presence_too_far';
  END IF;

  UPDATE participations SET confirmed_present = TRUE WHERE id = v_participation_id;
  PERFORM recalculate_reliability_score(v_user_id);
  PERFORM notify_presence_confirmed(v_user_id, p_activity_id, p_skip_push);

  -- Rule A: a non-creator confirming proves the meetup happened → the creator
  -- (organiser) was there. Auto-validate them.
  IF v_creator_id IS NOT NULL AND v_creator_id != v_user_id THEN
    UPDATE participations
    SET confirmed_present = TRUE
    WHERE activity_id = p_activity_id
      AND user_id = v_creator_id
      AND status = 'accepted'
      AND confirmed_present IS NULL;
    GET DIAGNOSTICS v_creator_flipped = ROW_COUNT;
    IF v_creator_flipped > 0 THEN
      PERFORM recalculate_reliability_score(v_creator_id);
      PERFORM notify_presence_confirmed(v_creator_id, p_activity_id, p_skip_push);
    END IF;
  END IF;
END;
$$;

-- ============================================================================
-- B+C. notify_presence_validate_warning — gate >= 3 (no self-validate nags at
--      2), and exclude the creator (their presence comes from others).
-- ============================================================================
CREATE OR REPLACE FUNCTION public.notify_presence_validate_warning(p_activity_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
BEGIN
  SELECT id, title, status, starts_at, duration, requires_presence, creator_id
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status NOT IN ('in_progress', 'completed') THEN RETURN; END IF;

  IF now() < v_activity.starts_at + (v_activity.duration / 2) THEN RETURN; END IF;
  IF now() >= v_activity.starts_at + v_activity.duration THEN RETURN; END IF;

  -- Peer testimony (and thus the self-validate nag) only applies from 3.
  IF (SELECT count(*) FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted') < 3 THEN
    RETURN;
  END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND p.confirmed_present IS NULL
      AND p.user_id != v_activity.creator_id   -- Rule B: creator not nagged
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

-- ============================================================================
-- B+C. notify_presence_validate_overdue — same gate >= 3 and creator exclusion.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.notify_presence_validate_overdue(p_activity_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
BEGIN
  SELECT id, title, status, starts_at, duration, requires_presence, creator_id
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF v_activity.status != 'completed' THEN RETURN; END IF;

  IF now() < v_activity.starts_at + v_activity.duration + INTERVAL '1 hour' THEN RETURN; END IF;
  IF now() > v_activity.starts_at + v_activity.duration + INTERVAL '1 hour 30 minutes' THEN RETURN; END IF;

  IF (SELECT count(*) FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted') < 3 THEN
    RETURN;
  END IF;

  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND p.confirmed_present IS NULL
      AND p.user_id != v_activity.creator_id   -- Rule B: creator not nagged
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

-- ============================================================================
-- C. close_presence_window_for — 2-person finalisation: QR/geo only. No
--    non-creator confirmation → expire + wipe (no penalty). Never FALSE-flip
--    at 2. 3+ keeps the existing FALSE-flip.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.close_presence_window_for(p_activity_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
  v_accepted_count INTEGER;
BEGIN
  SELECT id, status, starts_at, duration, requires_presence, creator_id
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.status != 'completed' THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF now() <= v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' THEN RETURN; END IF;

  SELECT count(*) INTO v_accepted_count
  FROM participations
  WHERE activity_id = p_activity_id AND status = 'accepted';

  -- Solo (creator alone): "absent" is undefined. Leave NULL untouched.
  IF v_accepted_count < 2 THEN RETURN; END IF;

  -- Rule C — exactly 2: presence only via QR/geo (peer testimony is circular).
  -- A non-creator confirmation auto-validates both (rule A), so its ABSENCE
  -- means the meetup wasn't verifiable → re-expire, wipe any lone self-
  -- validation so nothing counts, and never penalise.
  IF v_accepted_count = 2 THEN
    IF NOT EXISTS (
      SELECT 1 FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted'
        AND user_id != v_activity.creator_id AND confirmed_present = TRUE
    ) THEN
      PERFORM set_config('junto.bypass_lock', 'true', true);
      UPDATE activities SET status = 'expired', updated_at = now()
      WHERE id = p_activity_id AND status = 'completed';
      FOR v_target IN
        SELECT user_id FROM participations
        WHERE activity_id = p_activity_id AND status = 'accepted'
          AND confirmed_present IS NOT NULL
      LOOP
        UPDATE participations SET confirmed_present = NULL
        WHERE activity_id = p_activity_id AND user_id = v_target.user_id AND status = 'accepted';
        PERFORM recalculate_reliability_score(v_target.user_id);
      END LOOP;
    END IF;
    RETURN;
  END IF;

  -- 3+ : the existing peer-testimony finalisation — mark proven no-shows absent.
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

-- ============================================================================
-- C. peer_validate_presence — peer testimony needs 3+. Reject at 2 (use
--    QR/geo). Removes the old creator-direct-flip-at-2 special case.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.peer_validate_presence(p_voted_id uuid, p_activity_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_voter_present BOOLEAN;
  v_voted_status TEXT;
  v_voted_present BOOLEAN;
  v_vote_count INTEGER;
  v_accepted_count INTEGER;
  v_flipped INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_voted_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM pg_advisory_xact_lock(
    hashtext('peer_validate:' || p_activity_id::text || ':' || p_voted_id::text)
  );

  SELECT id, creator_id, status, starts_at, duration, requires_presence
  INTO v_activity
  FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL OR v_activity.status != 'completed' OR v_activity.requires_presence IS NOT TRUE THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF now() < v_activity.starts_at + v_activity.duration + INTERVAL '15 minutes' THEN
    RAISE EXCEPTION 'junto.peer_review_window_not_open';
  END IF;

  IF v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' < now() THEN
    RAISE EXCEPTION 'junto.peer_review_window_closed';
  END IF;

  SELECT count(*) INTO v_accepted_count
  FROM participations
  WHERE activity_id = p_activity_id AND status = 'accepted';

  -- Rule C: peer testimony is circular below 3 participants — use QR/geo.
  IF v_accepted_count < 3 THEN
    RAISE EXCEPTION 'junto.peer_review_unavailable';
  END IF;

  SELECT status, confirmed_present INTO v_voted_status, v_voted_present
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = p_voted_id
  FOR UPDATE;

  IF v_voted_status IS NULL OR v_voted_status != 'accepted' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_voted_present IS NOT NULL THEN
    RAISE EXCEPTION 'junto.peer_already_validated';
  END IF;

  SELECT confirmed_present INTO v_voter_present
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id AND status = 'accepted';
  IF v_voter_present IS NOT TRUE THEN
    RAISE EXCEPTION 'junto.peer_voter_not_present';
  END IF;

  INSERT INTO peer_validations (voter_id, voted_id, activity_id, created_at)
  VALUES (v_user_id, p_voted_id, p_activity_id, now())
  ON CONFLICT DO NOTHING;

  SELECT count(*) INTO v_vote_count
  FROM peer_validations
  WHERE activity_id = p_activity_id AND voted_id = p_voted_id;

  IF v_vote_count >= 2 THEN
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE participations
    SET confirmed_present = TRUE
    WHERE activity_id = p_activity_id
      AND user_id = p_voted_id
      AND status = 'accepted'
      AND confirmed_present IS NULL;
    GET DIAGNOSTICS v_flipped = ROW_COUNT;
    IF v_flipped > 0 THEN
      PERFORM recalculate_reliability_score(p_voted_id);
      PERFORM notify_presence_confirmed(p_voted_id, p_activity_id);
    END IF;
  END IF;
END;
$$;

-- ============================================================================
-- C. notify_peer_review_closing — no peer-review nudge at 2 (gate >= 3).
-- ============================================================================
CREATE OR REPLACE FUNCTION public.notify_peer_review_closing(p_activity_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_activity RECORD;
  v_target RECORD;
BEGIN
  SELECT id, title, status, starts_at, duration, requires_presence, creator_id
  INTO v_activity FROM activities WHERE id = p_activity_id;

  IF v_activity IS NULL THEN RETURN; END IF;
  IF v_activity.status != 'completed' THEN RETURN; END IF;
  IF v_activity.requires_presence IS NOT TRUE THEN RETURN; END IF;
  IF now() < v_activity.starts_at + v_activity.duration + INTERVAL '22 hours' THEN RETURN; END IF;
  IF now() > v_activity.starts_at + v_activity.duration + INTERVAL '24 hours' THEN RETURN; END IF;

  -- Rule C: no peer review below 3 participants (QR/geo only at 2).
  IF (SELECT count(*) FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted') < 3 THEN
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

  -- (b) Warn the still-unconfirmed attendees themselves, before the end+24h
  --     auto-FALSE penalty. Rule B: never the creator (their presence comes
  --     from the auto-flip / peers, not a self-action).
  FOR v_target IN
    SELECT p.user_id
    FROM participations p
    WHERE p.activity_id = p_activity_id
      AND p.status = 'accepted'
      AND p.confirmed_present IS NULL
      AND p.user_id != v_activity.creator_id
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
