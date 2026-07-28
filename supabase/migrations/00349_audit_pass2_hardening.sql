-- ============================================================================
-- 00349 — Second adversarial audit pass: residual hardening.
--
-- Three independent reviewers (not the author) re-checked 00344–00348. The
-- fixes held (invite gate proven closed, demo curtain regression-free), but the
-- fresh eyes surfaced 5 residuals + 1 optional parity item. All fixed here.
--
--   1. add_contact  — the silent no-op (00348) removed the *error* signal but a
--      caller could still read back get_contacts(): a known-not-suspended target
--      that is ABSENT after add ⇒ it blocks the caller (directional block
--      oracle). Close it at the source: DROP the block check. Contacts is a
--      one-way private address book with no notification to the target, so a
--      blocker sitting in the caller's private roster leaks nothing to the
--      blocker; block enforcement still lives where it matters (invite +
--      messaging paths, both directions).                        [MEDIUM]
--   2. pro_community_photos — the only demo-bearing read surface 00347 missed;
--      it is anon-readable. Add the same demo gate as its sibling photo tables.
--      Nothing leaks today (no community photos seeded on the demo pro) but the
--      curtain must be complete by construction, not by absence of rows. [MEDIUM]
--   3. get_transport_summary — public existence branch had no demo gate: a
--      non-admin could confirm the demo activities exist and (if trajets were
--      ever seeded) read departure cities. Add the demo gate.        [LOW]
--   4. add_favorite (offering) — required pp.status='approved' which the read
--      view (pro_offerings_with_coords) does NOT: an offering still visible on
--      the map after its pro was un-approved was wrongly non-favoritable. Mirror
--      the view — drop the approved predicate.                       [LOW]
--   5. add_favorite (cap) — the 500 count ran before ON CONFLICT, so a user at
--      exactly 500 re-favoriting an ALREADY-favorited target got junto.
--      favorite_cap instead of an idempotent no-op. Only cap genuinely-new
--      favorites.                                                    [LOW]
--   6. invite_users_to_activity — shared the 10-pending cap with send_contact_
--      request but under a DIFFERENT advisory-lock key, so concurrent calls to
--      both could transiently exceed 10. Serialize on the SAME key. (Verbatim
--      copy of 00344; only the lock key changes.)                    [LOW/opt]
--
-- All demo clauses are `is_demo = false OR demo_content_visible()` — TRUE for
-- real content, so no regression. Reviewer-confirmed safe by construction.
-- ============================================================================

-- 1. add_contact — drop the block check (close the get_contacts readback oracle).
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

  -- Target conditions: silent no-op (indistinguishable from success). No block
  -- check — a blocker landing in the caller's private roster leaks nothing (no
  -- notification, and invite/messaging still enforce blocking both ways).
  -- Suspension IS already public via public_profiles, so gating on it here
  -- reveals nothing new.
  IF p_contact_id IS NULL OR p_contact_id = v_user_id THEN RETURN; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_contact_id AND suspended_at IS NULL) THEN RETURN; END IF;

  INSERT INTO contacts (owner_id, contact_id)
  VALUES (v_user_id, p_contact_id)
  ON CONFLICT (owner_id, contact_id) DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION add_contact(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION add_contact(UUID) TO authenticated;

-- 2. pro_community_photos — add the demo gate (mirror 00347's photo-table pattern).
ALTER POLICY pro_community_photos_public_read ON public.pro_community_photos
  USING (
    NOT private.user_is_suspended(pro_id)
    AND (
      demo_content_visible()
      OR EXISTS (
        SELECT 1 FROM pro_profiles dp
        WHERE dp.user_id = pro_community_photos.pro_id AND dp.is_demo = false
      )
    )
  );

-- 3. get_transport_summary — add the demo gate to the existence check.
CREATE OR REPLACE FUNCTION get_transport_summary(
  p_activity_id UUID
)
RETURNS TABLE (
  transport_type TEXT,
  count INTEGER,
  total_seats INTEGER,
  cities TEXT[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities a
    WHERE a.id = p_activity_id
      AND a.status IN ('published', 'in_progress')
      AND a.deleted_at IS NULL
      AND (a.is_demo = false OR demo_content_visible())
      AND (
        a.visibility IN ('public', 'approval')
        OR a.creator_id = v_user_id
        OR EXISTS (
          SELECT 1 FROM participations p
          WHERE p.activity_id = a.id AND p.user_id = v_user_id
        )
      )
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  RETURN QUERY
  SELECT
    p.transport_type,
    count(*)::int AS count,
    COALESCE(sum(p.transport_seats)::int, 0) AS total_seats,
    array_agg(DISTINCT p.transport_from_name) FILTER (WHERE p.transport_from_name IS NOT NULL) AS cities
  FROM participations p
  WHERE p.activity_id = p_activity_id
    AND p.status = 'accepted'
    AND p.transport_type IS NOT NULL
  GROUP BY p.transport_type
  ORDER BY count DESC;
END;
$$;
REVOKE ALL ON FUNCTION get_transport_summary FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION get_transport_summary FROM anon;
GRANT EXECUTE ON FUNCTION get_transport_summary TO authenticated;

-- 4 + 5. add_favorite — mirror the offering read view (drop approved gate) and
--         only apply the 500 cap to genuinely-new favorites.
CREATE OR REPLACE FUNCTION add_favorite(p_kind TEXT, p_id UUID)
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
  IF p_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  -- Cap only NEW favorites — re-favoriting an existing target stays an
  -- idempotent no-op even at the boundary.
  IF (SELECT count(*) FROM favorites WHERE owner_id = v_user_id) >= 500
     AND NOT EXISTS (
       SELECT 1 FROM favorites
       WHERE owner_id = v_user_id
         AND ( (p_kind = 'activity' AND activity_id = p_id)
            OR (p_kind = 'offering' AND offering_id = p_id)
            OR (p_kind = 'pro'      AND pro_id = p_id) )
     ) THEN
    RAISE EXCEPTION 'junto.favorite_cap';
  END IF;

  IF p_kind = 'activity' THEN
    IF NOT EXISTS (
      SELECT 1 FROM activities a
      WHERE a.id = p_id
        AND a.deleted_at IS NULL
        AND a.status IN ('published', 'in_progress')
        AND (a.is_demo = false OR demo_content_visible())
        AND (
          a.visibility IN ('public', 'approval')
          OR (
            a.visibility IN ('private_link', 'private_link_approval')
            AND (
              a.creator_id = v_user_id
              OR EXISTS (SELECT 1 FROM participations p WHERE p.activity_id = a.id AND p.user_id = v_user_id AND p.status = 'accepted')
            )
          )
        )
        AND NOT EXISTS (SELECT 1 FROM users cu WHERE cu.id = a.creator_id AND cu.suspended_at IS NOT NULL)
        AND a.creator_id NOT IN (SELECT blocked_id FROM blocked_users WHERE blocker_id = v_user_id)
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    INSERT INTO favorites (owner_id, activity_id) VALUES (v_user_id, p_id) ON CONFLICT DO NOTHING;

  ELSIF p_kind = 'offering' THEN
    -- Mirror pro_offerings_with_coords: gate on suspension + demo only (NOT the
    -- parent pro's approved status — the view shows the offering regardless).
    IF NOT EXISTS (
      SELECT 1 FROM pro_offerings o
      JOIN users u ON u.id = o.pro_id
      WHERE o.id = p_id AND u.suspended_at IS NULL
        AND (o.is_demo = false OR demo_content_visible())
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    INSERT INTO favorites (owner_id, offering_id) VALUES (v_user_id, p_id) ON CONFLICT DO NOTHING;

  ELSIF p_kind = 'pro' THEN
    IF NOT EXISTS (
      SELECT 1 FROM pro_profiles p
      JOIN users u ON u.id = p.user_id
      WHERE p.user_id = p_id AND p.status = 'approved' AND u.suspended_at IS NULL
        AND (p.is_demo = false OR demo_content_visible())
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    INSERT INTO favorites (owner_id, pro_id) VALUES (v_user_id, p_id) ON CONFLICT DO NOTHING;

  ELSE
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION add_favorite(TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION add_favorite(TEXT, UUID) TO authenticated;

-- 6. invite_users_to_activity — verbatim 00344, ONLY the advisory-lock key
--    changes to '_contact_request' so it serializes on the SAME lock as
--    send_contact_request (shared 10-pending cap → no concurrent overshoot).
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
