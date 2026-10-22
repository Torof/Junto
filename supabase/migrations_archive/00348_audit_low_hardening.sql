-- ============================================================================
-- 00348 — Audit LOW/INFO hardening (contacts + favorites).
--
--   • add_contact: target-side failures become SILENT no-ops (was RAISE) so the
--     success/error signal can no longer be used to detect that a known user
--     now blocks / suspended / deleted the caller (oracle). Caller-side checks
--     (auth, own suspension) still raise — that's the caller's own state.
--   • add_favorite: a per-user cap (500) — anti-bloat / abuse. Branch gates
--     unchanged (mirror the read views, from 00345).
--   • remove_contact / remove_favorite: add the caller suspension check for
--     symmetry with the add path.
-- ============================================================================

-- add_contact — silent target checks (no oracle).
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

  -- Target conditions: silent no-op (indistinguishable from success) so the
  -- caller can't probe another user's block/suspension/existence state.
  IF p_contact_id IS NULL OR p_contact_id = v_user_id THEN RETURN; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_contact_id AND suspended_at IS NULL) THEN RETURN; END IF;
  IF EXISTS (
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = v_user_id AND blocked_id = p_contact_id)
       OR (blocker_id = p_contact_id AND blocked_id = v_user_id)
  ) THEN RETURN; END IF;

  INSERT INTO contacts (owner_id, contact_id)
  VALUES (v_user_id, p_contact_id)
  ON CONFLICT (owner_id, contact_id) DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION add_contact(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION add_contact(UUID) TO authenticated;

-- remove_contact — add the caller suspension check.
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
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  DELETE FROM contacts WHERE owner_id = v_user_id AND contact_id = p_contact_id;
END;
$$;
REVOKE ALL ON FUNCTION remove_contact(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION remove_contact(UUID) TO authenticated;

-- add_favorite — same branch gates as 00345, plus a 500-per-user cap.
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
  IF (SELECT count(*) FROM favorites WHERE owner_id = v_user_id) >= 500 THEN
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
    IF NOT EXISTS (
      SELECT 1 FROM pro_offerings o
      JOIN pro_profiles pp ON pp.user_id = o.pro_id
      JOIN users u ON u.id = o.pro_id
      WHERE o.id = p_id AND u.suspended_at IS NULL AND pp.status = 'approved'
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

-- remove_favorite — add the caller suspension check.
CREATE OR REPLACE FUNCTION remove_favorite(p_kind TEXT, p_id UUID)
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

  IF p_kind = 'activity' THEN
    DELETE FROM favorites WHERE owner_id = v_user_id AND activity_id = p_id;
  ELSIF p_kind = 'offering' THEN
    DELETE FROM favorites WHERE owner_id = v_user_id AND offering_id = p_id;
  ELSIF p_kind = 'pro' THEN
    DELETE FROM favorites WHERE owner_id = v_user_id AND pro_id = p_id;
  ELSE
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION remove_favorite(TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION remove_favorite(TEXT, UUID) TO authenticated;
