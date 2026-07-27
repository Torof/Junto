-- ============================================================================
-- 00341 — Contacts (one-way personal roster) + recent-partners suggestions +
--          batch "invite to activity".
--
-- Product intent (Scott 2026-07-27): contacts is a private, one-directional
-- address book (you add someone; they don't see it) whose ONLY job is to make
-- INVITING partners fast. Invite = reuse the existing `shared_activity` card
-- primitive (a tappable activity card in a DM — respects "no auto-linked URLs
-- in messages"). The invite picker draws from two sources: manual contacts +
-- auto "recent partners" (people you co-participated with) so it's never empty.
-- Logistical, not social: no acceptance flow, no notification on being added.
-- ============================================================================

-- ============================================================================
-- 1. TABLE contacts — one-way (owner added contact). Writes via functions only.
-- ============================================================================
CREATE TABLE contacts (
  owner_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  contact_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (owner_id, contact_id),
  CHECK (owner_id <> contact_id)
);

CREATE INDEX contacts_owner_idx ON contacts(owner_id, created_at DESC);

ALTER TABLE contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE contacts FORCE ROW LEVEL SECURITY;

-- You can only ever read your OWN contacts (it's a private list).
CREATE POLICY contacts_select_own ON contacts
  FOR SELECT TO authenticated
  USING (owner_id = auth.uid());

-- No INSERT/UPDATE/DELETE policies — SECURITY DEFINER functions are the only
-- write path. There is no UPDATE path at all (add/remove only), so no
-- whitelist trigger is needed.
REVOKE ALL ON contacts FROM anon;
GRANT SELECT ON contacts TO authenticated;

-- ============================================================================
-- 2. add_contact — auth + non-suspended; target exists/non-suspended; not self;
--    no block either way. Silent (no notification to the contact).
-- ============================================================================
CREATE OR REPLACE FUNCTION add_contact(p_contact_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_contact_id IS NULL OR p_contact_id = v_user_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_contact_id AND suspended_at IS NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = p_contact_id)
       OR (blocker_id = p_contact_id AND blocked_id = v_user_id)
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  INSERT INTO contacts (owner_id, contact_id)
  VALUES (v_user_id, p_contact_id)
  ON CONFLICT (owner_id, contact_id) DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION add_contact(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION add_contact(UUID) TO authenticated;

-- ============================================================================
-- 3. remove_contact — delete your own row.
-- ============================================================================
CREATE OR REPLACE FUNCTION remove_contact(p_contact_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  DELETE FROM contacts WHERE owner_id = v_user_id AND contact_id = p_contact_id;
END;
$$;
REVOKE ALL ON FUNCTION remove_contact(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION remove_contact(UUID) TO authenticated;

-- ============================================================================
-- 4. get_contacts — the caller's contacts, joined to public_profiles (which
--    excludes suspended users), most-recent first.
-- ============================================================================
CREATE OR REPLACE FUNCTION get_contacts()
RETURNS TABLE (id UUID, display_name TEXT, avatar_url TEXT, created_at TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT pp.id, pp.display_name, pp.avatar_url, c.created_at
  FROM contacts c
  JOIN public_profiles pp ON pp.id = c.contact_id
  WHERE c.owner_id = v_user_id
  ORDER BY c.created_at DESC;
END;
$$;
REVOKE ALL ON FUNCTION get_contacts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_contacts() TO authenticated;

-- ============================================================================
-- 5. get_recent_partners — people you co-participated with on recent PAST
--    outings (creator or accepted participant), excluding self, existing
--    contacts, and blocked users. public_profiles JOIN drops suspended ones.
-- ============================================================================
CREATE OR REPLACE FUNCTION get_recent_partners()
RETURNS TABLE (id UUID, display_name TEXT, avatar_url TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH my_activities AS (
    SELECT a.id, a.starts_at, a.creator_id
    FROM activities a
    WHERE a.deleted_at IS NULL
      AND a.starts_at <= now()
      AND a.starts_at > now() - INTERVAL '180 days'
      AND (
        a.creator_id = v_user_id
        OR EXISTS (
          SELECT 1 FROM participations p
          WHERE p.activity_id = a.id AND p.user_id = v_user_id AND p.status = 'accepted'
        )
      )
  ),
  partners AS (
    SELECT ma.creator_id AS uid, ma.starts_at AS at
    FROM my_activities ma
    WHERE ma.creator_id <> v_user_id
    UNION ALL
    SELECT p.user_id AS uid, ma.starts_at AS at
    FROM my_activities ma
    JOIN participations p
      ON p.activity_id = ma.id AND p.status = 'accepted' AND p.user_id <> v_user_id
  ),
  ranked AS (
    SELECT uid, max(at) AS last_at
    FROM partners
    GROUP BY uid
  )
  SELECT pp.id, pp.display_name, pp.avatar_url
  FROM ranked r
  JOIN public_profiles pp ON pp.id = r.uid
  WHERE r.uid NOT IN (SELECT contact_id FROM contacts WHERE owner_id = v_user_id)
    AND r.uid NOT IN (SELECT blocked_id FROM blocked_users WHERE blocker_id = v_user_id)
    AND r.uid NOT IN (SELECT blocker_id FROM blocked_users WHERE blocked_id = v_user_id)
  ORDER BY r.last_at DESC
  LIMIT 20;
END;
$$;
REVOKE ALL ON FUNCTION get_recent_partners() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_recent_partners() TO authenticated;

-- ============================================================================
-- 6. invite_users_to_activity — batch "invite": drop the shared_activity card
--    into each selected user's DM (+ push), reusing the primitive from
--    share_activity_message. Mirrors its share gate (public / creator /
--    approval-participant). Cap 20 targets, 60 shares/hour, 24h per-target
--    dedup. Returns how many were actually invited.
-- ============================================================================
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
  v_recent INTEGER;
  v_n INTEGER;
  v_target UUID;
  v_u1 UUID;
  v_u2 UUID;
  v_conv_id UUID;
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

  SELECT id, title, visibility, deleted_at, creator_id INTO v_activity
  FROM activities WHERE id = p_activity_id;
  IF v_activity.id IS NULL OR v_activity.deleted_at IS NOT NULL THEN
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

  -- Combined hourly cap on shared_activity messages (shared with the per-DM
  -- share). Serialise so the count + inserts are atomic.
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_invite_activity'));
  SELECT count(*) INTO v_recent
  FROM private_messages
  WHERE sender_id = v_user_id
    AND metadata->>'type' = 'shared_activity'
    AND created_at > now() - INTERVAL '1 hour';
  IF v_recent + v_n > 60 THEN RAISE EXCEPTION 'junto.rate_limited'; END IF;

  v_content := 'Je t''invite sur cette sortie 🙌' || E'\n« ' || v_activity.title || ' »';
  SELECT display_name INTO v_sender_name FROM users WHERE id = v_user_id;
  SELECT value INTO v_secret FROM app_config WHERE name = 'push_webhook_secret';

  FOR v_target IN SELECT DISTINCT unnest(p_user_ids) LOOP
    -- Skip invalid / self / suspended / blocked / already-invited-recently.
    CONTINUE WHEN v_target IS NULL OR v_target = v_user_id;
    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM users WHERE id = v_target AND suspended_at IS NULL);
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM blocked_users
      WHERE (blocker_id = v_user_id AND blocked_id = v_target)
         OR (blocker_id = v_target AND blocked_id = v_user_id)
    );
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM private_messages
      WHERE sender_id = v_user_id AND receiver_id = v_target
        AND metadata->>'type' = 'shared_activity'
        AND (metadata->>'activity_id')::uuid = p_activity_id
        AND created_at > now() - INTERVAL '24 hours'
    );

    -- Get or create the (ordered) conversation.
    IF v_user_id < v_target THEN v_u1 := v_user_id; v_u2 := v_target;
    ELSE v_u1 := v_target; v_u2 := v_user_id; END IF;
    SELECT id INTO v_conv_id FROM conversations WHERE user_1 = v_u1 AND user_2 = v_u2;
    IF v_conv_id IS NULL THEN
      INSERT INTO conversations (user_1, user_2, initiated_by, created_at)
      VALUES (v_u1, v_u2, v_user_id, now())
      RETURNING id INTO v_conv_id;
    END IF;

    INSERT INTO private_messages (conversation_id, sender_id, receiver_id, content, metadata, created_at)
    VALUES (
      v_conv_id, v_user_id, v_target, v_content,
      jsonb_build_object('type', 'shared_activity', 'activity_id', p_activity_id),
      now()
    );
    UPDATE conversations SET last_message_at = now() WHERE id = v_conv_id;

    IF v_secret IS NOT NULL THEN
      PERFORM net.http_post(
        url := 'https://lvjlthzdydzatcvwwriu.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-junto-push-secret', v_secret),
        body := jsonb_build_object(
          'user_id', v_target,
          'title', coalesce(v_sender_name, 'Junto'),
          'body', '📍 ' || v_activity.title,
          'data', jsonb_build_object('conversation_id', v_conv_id, 'activity_id', p_activity_id, 'type', 'shared_activity'),
          'collapseId', 'message-' || v_conv_id::text
        )
      );
    END IF;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION invite_users_to_activity(UUID, UUID[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION invite_users_to_activity(UUID, UUID[]) TO authenticated;
