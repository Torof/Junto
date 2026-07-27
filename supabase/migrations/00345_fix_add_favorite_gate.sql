-- ============================================================================
-- 00345 — SECURITY FIX: add_favorite visibility checks must mirror the read
--          gates (audit finding, MEDIUM).
--
-- The previous add_favorite only checked "not deleted + published" for
-- activities (and suspension only for offerings/pros), which was weaker than
-- what the read views/policies actually expose. That let a caller (a) favorite
-- admin-only DEMO content, (b) confirm the existence of a private_link activity
-- they aren't part of (success/fail oracle), (c) favorite content of a
-- suspended or blocking creator. Fix: each branch now mirrors its read gate
-- exactly — activities_with_coords (00333), pro_offerings_with_coords (00334),
-- pro_profiles_select (00334/00277) — including the demo predicate.
-- ============================================================================
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

  IF p_kind = 'activity' THEN
    -- Mirror activities_with_coords WHERE: not deleted, published/in_progress,
    -- demo gate, visibility (private_link only for creator/accepted member),
    -- creator not suspended, creator not blocking the caller.
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
              OR EXISTS (
                SELECT 1 FROM participations p
                WHERE p.activity_id = a.id AND p.user_id = v_user_id AND p.status = 'accepted'
              )
            )
          )
        )
        AND NOT EXISTS (SELECT 1 FROM users cu WHERE cu.id = a.creator_id AND cu.suspended_at IS NOT NULL)
        AND a.creator_id NOT IN (SELECT blocked_id FROM blocked_users WHERE blocker_id = v_user_id)
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    INSERT INTO favorites (owner_id, activity_id) VALUES (v_user_id, p_id) ON CONFLICT DO NOTHING;

  ELSIF p_kind = 'offering' THEN
    -- Mirror pro_offerings_with_coords: pro not suspended + demo gate
    -- (+ approved parent, for parity with the creation gate).
    IF NOT EXISTS (
      SELECT 1 FROM pro_offerings o
      JOIN pro_profiles pp ON pp.user_id = o.pro_id
      JOIN users u ON u.id = o.pro_id
      WHERE o.id = p_id
        AND u.suspended_at IS NULL
        AND pp.status = 'approved'
        AND (o.is_demo = false OR demo_content_visible())
    ) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
    INSERT INTO favorites (owner_id, offering_id) VALUES (v_user_id, p_id) ON CONFLICT DO NOTHING;

  ELSIF p_kind = 'pro' THEN
    -- Mirror pro_profiles_select: approved + not suspended + demo gate.
    IF NOT EXISTS (
      SELECT 1 FROM pro_profiles p
      JOIN users u ON u.id = p.user_id
      WHERE p.user_id = p_id
        AND p.status = 'approved'
        AND u.suspended_at IS NULL
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
