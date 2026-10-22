-- ============================================================================
-- 00401 — Let an admin in demo mode SHARE a demo activity into a chat/channel
-- (Scott 2026-09-05). share_activity_message blocked ALL is_demo activities →
-- in demo mode "Partager une sortie" always errored ("une erreur est survenue").
-- Same scoped relaxation as join_activity (00397): `is_demo AND NOT
-- demo_content_visible()` — an admin with demo mode ON can share demo activities;
-- everyone else stays blocked. (Reproduced from 00358; only the guard changes.)
-- ============================================================================

CREATE OR REPLACE FUNCTION share_activity_message(
  p_conversation_id UUID,
  p_activity_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_can_see BOOLEAN;
  v_recent INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM private.assert_can_send(p_conversation_id, v_user_id);

  SELECT id, title, visibility, deleted_at, creator_id, is_demo INTO v_activity
  FROM activities WHERE id = p_activity_id;
  IF v_activity.id IS NULL OR v_activity.deleted_at IS NOT NULL
     OR (v_activity.is_demo AND NOT demo_content_visible()) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  -- Share gate: public → anyone; private → creator only; approval → participant.
  v_can_see := v_activity.visibility = 'public'
    OR v_activity.creator_id = v_user_id
    OR (
      v_activity.visibility = 'approval'
      AND EXISTS (
        SELECT 1 FROM participations
        WHERE activity_id = p_activity_id AND user_id = v_user_id
          AND status IN ('accepted', 'pending')
      )
    );
  IF NOT v_can_see THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_share_activity'));
  SELECT count(*) INTO v_recent FROM messages
  WHERE sender_id = v_user_id AND metadata->>'type' = 'shared_activity'
    AND created_at > now() - INTERVAL '1 minute';
  IF v_recent >= 1 THEN RAISE EXCEPTION 'junto.share_rate_limit'; END IF;

  RETURN private.insert_rich_message(
    p_conversation_id, v_user_id,
    '📍 ' || regexp_replace(v_activity.title, '<[^>]*>', '', 'g'),
    jsonb_build_object('type', 'shared_activity', 'activity_id', p_activity_id)
  );
END;
$$;
REVOKE ALL ON FUNCTION share_activity_message(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION share_activity_message(UUID, UUID) TO authenticated;
