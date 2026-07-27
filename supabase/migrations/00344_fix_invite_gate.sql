-- ============================================================================
-- 00344 — SECURITY FIX: invite_users_to_activity must respect the connection-
--          request gate (00072).
--
-- The previous version minted `active` conversations directly (status defaulted
-- to 'active'), letting a caller open an unsolicited DM channel with ANY user
-- via any public activity — bypassing 00072's "all first-time DMs go through an
-- accept/decline request" invariant (audit finding, CRITICAL).
--
-- New behaviour, per target (Scott-validated, option B):
--   • an ACTIVE conversation already exists → drop the shared_activity card
--     (+ push), exactly like share_activity_message;
--   • NO conversation yet → send a gated CONNECTION REQUEST (pending_request)
--     carrying the invitation as its request message, capped by the system's
--     10-pending-requests limit;
--   • a pending_request / declined conversation exists → skip (00072 forbids
--     re-sending).
-- No function ever creates an `active` conversation for a non-connected pair.
-- ============================================================================

-- Allow 'invite' as a connection-request source.
DO $$
DECLARE v_cname text;
BEGIN
  SELECT conname INTO v_cname
  FROM pg_constraint
  WHERE conrelid = 'conversations'::regclass AND contype = 'c'
    AND pg_get_constraintdef(oid) ILIKE '%initiated_from%';
  IF v_cname IS NOT NULL THEN
    EXECUTE 'ALTER TABLE conversations DROP CONSTRAINT ' || quote_ident(v_cname);
  END IF;
END $$;
ALTER TABLE conversations ADD CONSTRAINT conversations_initiated_from_check
  CHECK (initiated_from IS NULL OR initiated_from IN ('profile', 'discovery', 'transport', 'invite'));

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

  -- Serialize the caller so the two caps + inserts stay atomic.
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_invite_activity'));

  SELECT count(*) INTO v_recent FROM private_messages
    WHERE sender_id = v_user_id AND metadata->>'type' = 'shared_activity'
      AND created_at > now() - INTERVAL '1 hour';
  SELECT count(*) INTO v_pending FROM conversations
    WHERE status = 'pending_request' AND (user_1 = v_user_id OR user_2 = v_user_id)
      AND initiated_from IS NOT NULL;

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
