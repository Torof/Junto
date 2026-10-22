-- ============================================================================
-- 00409 — Audit 2nd pass, phase 2 (M3 + LOW): close the invite-path oracle.
--
-- get_invitable_activities_for_dispo / send_discovery_invite read the TARGET's
-- active dispo with no reciprocity and no demo gate, so:
--   (M3) any authed user could probe another user's availability (sports/window)
--        and get a free unbounded oracle via junto.discovery_no_match — without
--        holding a matching dispo of their own.
--   (LOW) demo dispos (fixed UUIDs) could be read/invited by a non-admin.
-- Fix: (a) demo-gate the target lookup, and (b) require RECIPROCITY — the caller
-- must hold an active dispo whose sport ∩ zone ∩ window overlaps the target's
-- (the exact get_discovery_cards predicate). The client only surfaces "Inviter"
-- on a discovery card, which already implies this match → no legit regression;
-- the gate just enforces it server-side and collapses the direct-RPC oracle to
-- the already-visible card/zone surface. (Scott 2026-09-09, 2nd adversarial pass.)
-- ============================================================================

-- ---------- get_invitable_activities_for_dispo ----------
CREATE OR REPLACE FUNCTION get_invitable_activities_for_dispo(p_target_user_id UUID)
RETURNS TABLE (
  id UUID,
  title TEXT,
  sport_key TEXT,
  starts_at TIMESTAMPTZ,
  max_participants INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_dispo RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN RETURN; END IF;
  IF v_user_id = p_target_user_id THEN RETURN; END IF;
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = p_target_user_id)
       OR (blocker_id = p_target_user_id AND blocked_id = v_user_id)
  ) THEN RETURN; END IF;

  -- Reciprocity: the target must be one of MY discovery matches. Silent empty
  -- otherwise (no availability oracle for a non-match / demo dispo).
  IF NOT EXISTS (
    SELECT 1
    FROM discovery_availabilities me
    JOIN discovery_availabilities tgt
      ON tgt.user_id = p_target_user_id AND tgt.is_active
         AND (tgt.is_demo = false OR demo_content_visible())
    WHERE me.user_id = v_user_id AND me.is_active
      AND me.sport_keys && tgt.sport_keys
      AND tstzrange(me.window_start, me.window_end) && tstzrange(tgt.window_start, tgt.window_end)
      AND (me.radius_km IS NULL OR tgt.radius_km IS NULL
           OR ST_DWithin(me.base, tgt.base, (me.radius_km + tgt.radius_km) * 1000.0))
  ) THEN RETURN; END IF;

  SELECT d.sport_keys, d.window_start, d.window_end INTO v_dispo
  FROM discovery_availabilities d
  WHERE d.user_id = p_target_user_id AND d.is_active
    AND (d.is_demo = false OR demo_content_visible());
  IF NOT FOUND THEN RETURN; END IF;

  RETURN QUERY
  SELECT a.id, a.title, s.key, a.starts_at, a.max_participants
  FROM activities a
  JOIN sports s ON s.id = a.sport_id
  WHERE a.creator_id = v_user_id
    AND a.deleted_at IS NULL
    AND NOT a.is_demo
    AND a.status IN ('published', 'in_progress')
    AND s.key = ANY(v_dispo.sport_keys)
    AND a.starts_at BETWEEN v_dispo.window_start AND v_dispo.window_end
  ORDER BY a.starts_at ASC;
END;
$$;
REVOKE ALL ON FUNCTION get_invitable_activities_for_dispo(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_invitable_activities_for_dispo(UUID) TO authenticated;

-- ---------- send_discovery_invite ----------
CREATE OR REPLACE FUNCTION send_discovery_invite(
  p_target_user_id UUID,
  p_activity_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_conversation_id UUID;
  v_pending_count INTEGER;
  v_daily_count INTEGER;
  v_user_1 UUID;
  v_user_2 UUID;
  v_sender_name TEXT;
  v_activity RECORD;
  v_sport_key TEXT;
  v_dispo RECORD;
  v_clean_title TEXT;
  v_message TEXT;
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

  -- Reciprocity + demo gate: the target must be one of MY discovery matches.
  -- Generic failure (sensitive): don't reveal whether it's no-dispo vs no-match.
  IF NOT EXISTS (
    SELECT 1
    FROM discovery_availabilities me
    JOIN discovery_availabilities tgt
      ON tgt.user_id = p_target_user_id AND tgt.is_active
         AND (tgt.is_demo = false OR demo_content_visible())
    WHERE me.user_id = v_user_id AND me.is_active
      AND me.sport_keys && tgt.sport_keys
      AND tstzrange(me.window_start, me.window_end) && tstzrange(tgt.window_start, tgt.window_end)
      AND (me.radius_km IS NULL OR tgt.radius_km IS NULL
           OR ST_DWithin(me.base, tgt.base, (me.radius_km + tgt.radius_km) * 1000.0))
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- Activity must be mine, live, real.
  SELECT a.id, a.title, a.creator_id, a.status, a.deleted_at, a.is_demo, a.starts_at, a.sport_id
  INTO v_activity FROM activities a WHERE a.id = p_activity_id;
  IF v_activity.id IS NULL OR v_activity.deleted_at IS NOT NULL OR v_activity.is_demo
     OR v_activity.creator_id != v_user_id
     OR v_activity.status NOT IN ('published', 'in_progress') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  SELECT s.key INTO v_sport_key FROM sports s WHERE s.id = v_activity.sport_id;

  -- Match the chosen activity against the target's ACTIVE dispo (sport + date).
  SELECT d.sport_keys, d.window_start, d.window_end INTO v_dispo
  FROM discovery_availabilities d
  WHERE d.user_id = p_target_user_id AND d.is_active
    AND (d.is_demo = false OR demo_content_visible());
  IF NOT FOUND
     OR v_sport_key IS NULL
     OR NOT (v_sport_key = ANY(v_dispo.sport_keys))
     OR v_activity.starts_at < v_dispo.window_start
     OR v_activity.starts_at > v_dispo.window_end THEN
    RAISE EXCEPTION 'junto.discovery_no_match';
  END IF;

  IF v_user_id < p_target_user_id THEN
    v_user_1 := v_user_id; v_user_2 := p_target_user_id;
  ELSE
    v_user_1 := p_target_user_id; v_user_2 := v_user_id;
  END IF;

  SELECT id INTO v_conversation_id
  FROM conversations WHERE user_1 = v_user_1 AND user_2 = v_user_2;
  IF v_conversation_id IS NOT NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_contact_request'));

  SELECT count(*) INTO v_pending_count
  FROM conversations
  WHERE request_sender_id = v_user_id
    AND (
      status = 'pending_request'
      OR (status = 'declined' AND created_at > NOW() - INTERVAL '30 days')
    );
  IF v_pending_count >= 10 THEN RAISE EXCEPTION 'junto.contact_request_pending_cap'; END IF;

  SELECT count(*) INTO v_daily_count
  FROM conversations
  WHERE request_sender_id = v_user_id
    AND created_at > NOW() - INTERVAL '24 hours';
  IF v_daily_count >= 5 THEN RAISE EXCEPTION 'junto.contact_request_daily_cap'; END IF;

  v_clean_title := regexp_replace(v_activity.title, '<[^>]*>', '', 'g');
  v_message := 'Je t''invite à rejoindre « ' || v_clean_title || ' »';

  INSERT INTO conversations (
    user_1, user_2, initiated_by, status, initiated_from,
    request_sender_id, request_message, request_expires_at,
    pending_activity_id, created_at, last_message_at
  )
  VALUES (
    v_user_1, v_user_2, v_user_id, 'pending_request', 'invite',
    v_user_id, v_message, NOW() + INTERVAL '30 days',
    p_activity_id, NOW(), NOW()
  )
  RETURNING id INTO v_conversation_id;

  SELECT display_name INTO v_sender_name FROM public_profiles WHERE id = v_user_id;
  PERFORM create_notification(
    p_target_user_id,
    'contact_request',
    coalesce(v_sender_name, 'Quelqu''un') || ' t''invite à une sortie',
    v_clean_title,
    jsonb_build_object('conversation_id', v_conversation_id, 'from_user_id', v_user_id, 'activity_id', p_activity_id)
  );

  RETURN v_conversation_id;
END;
$$;
REVOKE ALL ON FUNCTION send_discovery_invite(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION send_discovery_invite(UUID, UUID) TO authenticated;
