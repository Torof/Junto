-- ============================================================================
-- 00350 — Live fixes from the messaging-design adversarial review (2026-08-04).
--
-- The design review of the unified messaging model audited the CURRENT prod
-- functions along the way and found four live issues, fixed here (Scott GO):
--
--   1. decline_contact_request was callable by the request SENDER — a
--      deterministic decline oracle (success ⇒ still pending, generic error ⇒
--      already declined). Add caller ≠ request_sender_id. Error stays the same
--      generic message on every failure path → no new distinguishability.
--   2. send_contact_request's 10-pending cap counted requests RECEIVED as well
--      as sent ((user_1=me OR user_2=me)) — strangers could consume the
--      victim's send quota. Count only requests the caller SENT.
--   3. The same cap freed a slot the moment the recipient declined — a
--      repeatable, attributable decline oracle (park 9 fillers + 1 target at
--      the cap, poll send). A declined request now occupies its slot until
--      created_at + 30 days — exactly as long as an untouched pending would
--      (expiry flips pending→declined on the same schedule), so decline
--      changes NOTHING the sender can measure. Same predicate ported to
--      invite_users_to_activity's shared counter.
--   4. join_activity had no demo gate: with the demo curtain ON a real user
--      could join a demo activity (public → instant accepted), polluting demo
--      data and minting fake "recent partner" edges. Generic reject.
--
-- The remaining review finding on live prod (conversations SELECT policy
-- exposing status='declined' to the sender via PostgREST) requires client
-- repointing and is deliberately NOT hot-fixed here — it is the first brick of
-- the messaging rebuild (curated reads). Interim risk documented: no real
-- users are active yet.
-- ============================================================================

-- 1. decline_contact_request — the sender can never call decline.
CREATE OR REPLACE FUNCTION decline_contact_request(
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
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT * INTO v_conv FROM conversations WHERE id = p_conversation_id;
  IF v_conv IS NULL OR v_conv.status != 'pending_request' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id != v_conv.user_1 AND v_user_id != v_conv.user_2 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Only the RECIPIENT may decline. Without this, the sender could probe the
  -- state of their own request (success = pending, error = declined).
  IF v_user_id = v_conv.request_sender_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  UPDATE conversations
  SET status = 'declined'
  WHERE id = p_conversation_id;

  -- No notification to sender (silent decline)
END;
$$;
REVOKE EXECUTE ON FUNCTION decline_contact_request FROM anon;
GRANT EXECUTE ON FUNCTION decline_contact_request TO authenticated;

-- 2 + 3. send_contact_request — sender-only cap counting, decline-blind slots.
CREATE OR REPLACE FUNCTION send_contact_request(
  p_target_user_id UUID,
  p_message TEXT,
  p_source TEXT DEFAULT 'profile'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_conversation_id UUID;
  v_pending_count INTEGER;
  v_daily_count INTEGER;
  v_user_1 UUID;
  v_user_2 UUID;
  v_sender_name TEXT;
  v_clean_message TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM users u WHERE u.id = v_user_id AND u.suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = p_target_user_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF NOT EXISTS (SELECT 1 FROM users u WHERE u.id = p_target_user_id AND u.suspended_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = p_target_user_id)
       OR (blocker_id = p_target_user_id AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id < p_target_user_id THEN
    v_user_1 := v_user_id; v_user_2 := p_target_user_id;
  ELSE
    v_user_1 := p_target_user_id; v_user_2 := v_user_id;
  END IF;

  SELECT id INTO v_conversation_id
  FROM conversations WHERE user_1 = v_user_1 AND user_2 = v_user_2;

  IF v_conversation_id IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM conversations WHERE id = v_conversation_id AND status = 'active') THEN
      RETURN v_conversation_id;
    END IF;
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Pending-count cap + daily cap. Both behind the same advisory lock
  -- so concurrent senders can't both squeeze past either bound.
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_contact_request'));

  -- Count only requests the caller SENT (a stranger's inbound requests must
  -- never consume the caller's quota), and keep DECLINED requests occupying
  -- their slot until created_at + 30 days — the exact lifetime an untouched
  -- pending would have had — so a decline is invisible to this counter.
  SELECT count(*) INTO v_pending_count
  FROM conversations
  WHERE request_sender_id = v_user_id
    AND (
      status = 'pending_request'
      OR (status = 'declined' AND created_at > NOW() - INTERVAL '30 days')
    );
  IF v_pending_count >= 10 THEN RAISE EXCEPTION 'junto.contact_request_pending_cap'; END IF;

  -- 5 requests / 24h regardless of acceptance state. Caps the
  -- "send fresh as old expire" attack on top of the static 10-pending
  -- cap (which doesn't bound velocity).
  SELECT count(*) INTO v_daily_count
  FROM conversations
  WHERE request_sender_id = v_user_id
    AND created_at > NOW() - INTERVAL '24 hours';
  IF v_daily_count >= 5 THEN RAISE EXCEPTION 'junto.contact_request_daily_cap'; END IF;

  IF p_message IS NULL OR char_length(trim(p_message)) < 1 OR char_length(p_message) > 500 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_clean_message := regexp_replace(trim(p_message), '<[^>]*>', '', 'g');

  INSERT INTO conversations (user_1, user_2, initiated_by, status, initiated_from, request_sender_id, request_message, request_expires_at, created_at, last_message_at)
  VALUES (v_user_1, v_user_2, v_user_id, 'pending_request', p_source, v_user_id, v_clean_message, NOW() + INTERVAL '30 days', NOW(), NOW())
  RETURNING id INTO v_conversation_id;

  SELECT display_name INTO v_sender_name FROM public_profiles WHERE id = v_user_id;

  PERFORM create_notification(
    p_target_user_id,
    'contact_request',
    coalesce(v_sender_name, 'Quelqu''un') || ' souhaite te contacter',
    '',
    jsonb_build_object('conversation_id', v_conversation_id, 'from_user_id', v_user_id)
  );

  RETURN v_conversation_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION send_contact_request FROM anon;
GRANT EXECUTE ON FUNCTION send_contact_request TO authenticated;

-- 3 (suite). invite_users_to_activity — same counter predicate (shared cap,
-- shared advisory lock). Verbatim 00349 body; ONLY the v_pending SELECT changes.
CREATE OR REPLACE FUNCTION invite_users_to_activity(p_activity_id UUID, p_user_ids UUID[])
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_can_share BOOLEAN;
  v_recent INTEGER;   -- shared_activity messages in the last hour (60 cap)
  v_pending INTEGER;  -- caller's pending connection requests (10 cap)
  v_n INTEGER;
  v_target UUID;
  v_u1 UUID;
  v_u2 UUID;
  v_conv RECORD;
  v_content TEXT;
  v_sender_name TEXT;
  v_secret TEXT;
  v_count INTEGER := 0;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_n := array_length(p_user_ids, 1);
  IF p_user_ids IS NULL OR v_n IS NULL OR v_n < 1 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF v_n > 20 THEN RAISE EXCEPTION 'junto.invite_cap'; END IF;

  SELECT id, title, visibility, deleted_at, creator_id, status INTO v_activity
  FROM activities WHERE id = p_activity_id;
  IF v_activity.id IS NULL OR v_activity.deleted_at IS NOT NULL
     OR v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Share gate (mirror share_activity_message): public → anyone; private →
  -- creator only; approval → any accepted/pending participant.
  v_can_share := v_activity.visibility = 'public'
    OR v_activity.creator_id = v_user_id
    OR (
      v_activity.visibility = 'approval'
      AND EXISTS (
        SELECT 1 FROM participations
        WHERE activity_id = p_activity_id AND user_id = v_user_id
          AND status IN ('accepted', 'pending')
      )
    );
  IF NOT v_can_share THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  v_content := 'Je t''invite sur cette sortie 🙌' || E'\n« ' || v_activity.title || ' »';
  SELECT display_name INTO v_sender_name FROM users WHERE id = v_user_id;
  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';

  -- Serialize the caller so the two caps + inserts stay atomic. Same lock key as
  -- send_contact_request so the shared 10-pending cap can't be raced across the
  -- two functions.
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_contact_request'));

  SELECT count(*) INTO v_recent FROM private_messages
    WHERE sender_id = v_user_id AND metadata->>'type' = 'shared_activity'
      AND created_at > now() - INTERVAL '1 hour';
  -- Same decline-blind, sender-only predicate as send_contact_request (00350).
  SELECT count(*) INTO v_pending FROM conversations
    WHERE request_sender_id = v_user_id
      AND (
        status = 'pending_request'
        OR (status = 'declined' AND created_at > now() - INTERVAL '30 days')
      );

  FOR v_target IN SELECT DISTINCT unnest(p_user_ids) LOOP
    CONTINUE WHEN v_target IS NULL OR v_target = v_user_id;
    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM users WHERE id = v_target AND suspended_at IS NULL);
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM blocked_users
      WHERE (blocker_id = v_user_id AND blocked_id = v_target)
         OR (blocker_id = v_target AND blocked_id = v_user_id)
    );

    IF v_user_id < v_target THEN v_u1 := v_user_id; v_u2 := v_target;
    ELSE v_u1 := v_target; v_u2 := v_user_id; END IF;
    SELECT id, status INTO v_conv FROM conversations WHERE user_1 = v_u1 AND user_2 = v_u2;

    IF v_conv.id IS NOT NULL AND v_conv.status = 'active' THEN
      -- Already connected → drop the tappable activity card (respect the 60/hr
      -- cap + 24h per-target dedup).
      CONTINUE WHEN v_recent >= 60;
      CONTINUE WHEN EXISTS (
        SELECT 1 FROM private_messages
        WHERE sender_id = v_user_id AND receiver_id = v_target
          AND metadata->>'type' = 'shared_activity'
          AND (metadata->>'activity_id')::uuid = p_activity_id
          AND created_at > now() - INTERVAL '24 hours'
      );
      INSERT INTO private_messages (conversation_id, sender_id, receiver_id, content, metadata, created_at)
        VALUES (v_conv.id, v_user_id, v_target, v_content,
                jsonb_build_object('type', 'shared_activity', 'activity_id', p_activity_id), now());
      UPDATE conversations SET last_message_at = now() WHERE id = v_conv.id;
      v_recent := v_recent + 1;
      IF v_secret IS NOT NULL THEN
        PERFORM net.http_post(
          url := 'https://lvjlthzdydzatcvwwriu.supabase.co/functions/v1/send-push',
          headers := jsonb_build_object('Content-Type', 'application/json', 'x-junto-push-secret', v_secret),
          body := jsonb_build_object(
            'user_id', v_target,
            'title', coalesce(v_sender_name, 'Junto'),
            'body', '📍 ' || v_activity.title,
            'data', jsonb_build_object('conversation_id', v_conv.id, 'activity_id', p_activity_id, 'type', 'shared_activity'),
            'collapseId', 'message-' || v_conv.id::text
          )
        );
      END IF;
      v_count := v_count + 1;

    ELSIF v_conv.id IS NULL THEN
      -- Not connected yet → send a gated connection request carrying the
      -- invitation (respect the 10-pending cap). The notifications INSERT is
      -- what fires the target's push (via the notifications→send-push trigger).
      CONTINUE WHEN v_pending >= 10;
      INSERT INTO conversations
        (user_1, user_2, initiated_by, status, initiated_from, request_sender_id, request_message, request_expires_at, created_at, last_message_at)
        VALUES (v_u1, v_u2, v_user_id, 'pending_request', 'invite', v_user_id, v_content, now() + INTERVAL '30 days', now(), now())
        ON CONFLICT (user_1, user_2) DO NOTHING;
      IF FOUND THEN
        v_pending := v_pending + 1;
        INSERT INTO notifications (user_id, type, title, body, data, created_at)
          VALUES (
            v_target, 'contact_request',
            coalesce(v_sender_name, 'Quelqu''un') || ' t''invite sur une sortie', '',
            jsonb_build_object('type', 'contact_request', 'from_user_id', v_user_id),
            now()
          );
        v_count := v_count + 1;
      END IF;

    -- else: a pending_request / declined conversation exists → skip (00072).
    END IF;
  END LOOP;

  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION invite_users_to_activity(UUID, UUID[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION invite_users_to_activity(UUID, UUID[]) TO authenticated;

-- 4. join_activity — demo activities are not joinable (curtain integrity:
-- no real participations on demo content, no fake recent-partner edges).
-- Verbatim 00301 body; ONLY the SELECT gains is_demo + one generic gate.
CREATE OR REPLACE FUNCTION join_activity(
  p_activity_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
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

  SELECT id, creator_id, status, visibility, max_participants, title, is_demo
  INTO v_activity
  FROM activities
  WHERE id = p_activity_id
  FOR UPDATE;

  IF v_activity IS NULL OR v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Demo content is a showcase, never joinable by real accounts.
  IF v_activity.is_demo THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF v_user_id = v_activity.creator_id THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  IF EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = v_activity.creator_id AND blocked_id = v_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT count(*) INTO v_current_count
  FROM participations
  WHERE activity_id = p_activity_id AND status = 'accepted';

  IF v_current_count >= COALESCE(v_activity.max_participants, 50) THEN
    RAISE EXCEPTION 'junto.activity_full';
  END IF;

  SELECT count(*) INTO v_hourly_count
  FROM participations
  WHERE user_id = v_user_id AND created_at > NOW() - INTERVAL '1 hour';

  IF v_hourly_count >= 10 THEN RAISE EXCEPTION 'junto.join_rate_limit'; END IF;

  IF v_activity.visibility IN ('public', 'private_link') THEN
    v_result_status := 'accepted';
  ELSE
    v_result_status := 'pending';
  END IF;

  SELECT id, status, refused_at INTO v_existing
  FROM participations
  WHERE activity_id = p_activity_id AND user_id = v_user_id;

  IF v_existing IS NOT NULL THEN
    IF v_existing.status = 'removed' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    IF v_existing.status IN ('accepted', 'pending') THEN RAISE EXCEPTION 'junto.already_joined'; END IF;
    IF v_existing.status = 'refused'
       AND v_existing.refused_at IS NOT NULL
       AND v_existing.refused_at > NOW() - INTERVAL '24 hours' THEN
      RAISE EXCEPTION 'junto.refuse_cooldown';
    END IF;

    -- Re-check capacity immediately before mutating. Activity row is
    -- still locked via FOR UPDATE above, but our count was read before
    -- handling pending state — refuse-then-rejoin within the lock
    -- holds, but defence-in-depth.
    IF v_result_status = 'accepted' THEN
      SELECT count(*) INTO v_current_count
      FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted';
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
      FROM participations
      WHERE activity_id = p_activity_id AND status = 'accepted';
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
      v_activity.creator_id,
      'join_request',
      'Nouvelle demande',
      v_user_name || ' souhaite rejoindre ' || v_activity.title,
      jsonb_build_object('activity_id', p_activity_id)
    );
  ELSE
    PERFORM notify_participant_joined(
      v_activity.creator_id,
      p_activity_id,
      v_user_name,
      v_activity.title
    );
  END IF;

  RETURN v_result_status;
END;
$$;
REVOKE EXECUTE ON FUNCTION join_activity FROM anon;
GRANT EXECUTE ON FUNCTION join_activity TO authenticated;
