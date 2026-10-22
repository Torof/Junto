-- Migration 00302: notification copy fixes (French), validated by Scott.
--
-- Pure string changes inside four existing functions, redefined verbatim
-- from their latest definitions (00205 / 00291 / 00219) except for:
--   1. seat_request_expired title: "Demande non répondue" -> "Demande sans réponse"
--   2. presence_validate_warning body: "enregistré comme absent à" -> "marqué absent pour"
--   3. peer_review_closing body: "Dernière chance pour valider" -> "de valider"
--   4. presence_validate_final body: tense fix "fenêtre fermée dans 2h" ->
--      "la fenêtre se ferme dans 2h" (+ "avant que ce soit compté")
--   5. contact_request_accepted: empty body -> "{name} a accepté ta demande de
--      contact" (display_name via public_profiles; one added SELECT).
-- Authorization chains untouched; CREATE OR REPLACE preserves ACLs.

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
      jsonb_build_object('activity_id', v_request.activity_id, 'seat_request_id', v_request.id)
    );
  END LOOP;
END;
$$;

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
        'Sinon tu seras marqué absent pour ' || v_activity.title,
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION
      WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

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
        'Dernière chance de valider tes co-participants — la fenêtre se ferme dans 2h',
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
        'Ta présence n''a pas été validée. Demande à un participant présent de te confirmer avant que ce soit compté comme une absence — la fenêtre se ferme dans 2h.',
        jsonb_build_object('activity_id', p_activity_id)
      );
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION accept_contact_request(
  p_conversation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_conv RECORD;
  v_sender_id UUID;
  v_accepter_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_conv FROM conversations WHERE id = p_conversation_id;
  IF v_conv IS NULL OR v_conv.status != 'pending_request' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = v_conv.request_sender_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF v_user_id != v_conv.user_1 AND v_user_id != v_conv.user_2 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_sender_id := v_conv.request_sender_id;

  -- Named body (2026-07-09): the accepted-contact card used to render an
  -- empty one-liner. public_profiles per house rules.
  SELECT display_name INTO v_accepter_name FROM public_profiles WHERE id = v_user_id;

  UPDATE conversations
  SET status = 'active', request_expires_at = NULL
  WHERE id = p_conversation_id;

  INSERT INTO private_messages (conversation_id, sender_id, receiver_id, content, created_at)
  VALUES (p_conversation_id, v_sender_id, v_user_id, v_conv.request_message, v_conv.created_at);

  PERFORM create_notification(
    v_sender_id,
    'contact_request_accepted',
    'Demande acceptée',
    coalesce(v_accepter_name, 'Quelqu''un') || ' a accepté ta demande de contact',
    jsonb_build_object('conversation_id', p_conversation_id)
  );
END;
$$;
