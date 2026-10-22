-- Migration 00321: admin audit log + first batch of admin capabilities
--
-- Charter: docs/ADMIN.md (validated by Scott 2026-07-13). Admin powers are
-- scoped, audited, and reason-bound. Foundation = an append-only admin_actions
-- log; every admin write records who/what/target/reason/when.
--
-- Batch 1: admin_actions table, an internal logger, unsuspend (a real gap —
-- nothing could lift a suspension), suspend-with-reason, and two audited
-- identity/ownership lookups (resolve a user, resolve a pro page's owner —
-- exactly what was missing when we hunted down "Air & water"). The three
-- existing admin functions (moderate_report / approve_pro / reject_pro) are
-- retrofitted to write to the audit log. Content takedown + the admin UI are
-- Batch 2. Boundaries kept: no DM access, no impersonation, no self-grant,
-- an admin cannot suspend another admin (admin status is managed at SQL level).

-- ============================================================================
-- TABLE: admin_actions (append-only audit log)
-- ============================================================================
CREATE TABLE admin_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id UUID REFERENCES users(id) ON DELETE SET NULL,  -- log survives admin deletion
  action TEXT NOT NULL,
  target_type TEXT,
  target_id UUID,
  reason TEXT,
  metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_admin_actions_created ON admin_actions(created_at DESC);
CREATE INDEX idx_admin_actions_target ON admin_actions(target_type, target_id);

ALTER TABLE admin_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_actions FORCE ROW LEVEL SECURITY;

-- Read: admin only. Append-only — no client writes ever (functions log via the
-- SECURITY DEFINER helper below); no UPDATE/DELETE policy at all.
CREATE POLICY "admin_actions_select_admin"
  ON admin_actions FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND is_admin = true));

REVOKE ALL ON admin_actions FROM anon;
REVOKE ALL ON admin_actions FROM authenticated;
GRANT SELECT ON admin_actions TO authenticated;

-- ============================================================================
-- Internal logger — called only by other SECURITY DEFINER admin functions
-- (they run as owner, so the REVOKE below doesn't block them). Not client-callable.
-- ============================================================================
CREATE OR REPLACE FUNCTION log_admin_action(
  p_admin UUID,
  p_action TEXT,
  p_target_type TEXT,
  p_target_id UUID,
  p_reason TEXT DEFAULT NULL,
  p_metadata JSONB DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO admin_actions (admin_id, action, target_type, target_id, reason, metadata)
  VALUES (p_admin, p_action, p_target_type, p_target_id, p_reason, p_metadata);
END;
$$;

REVOKE ALL ON FUNCTION log_admin_action(UUID, TEXT, TEXT, UUID, TEXT, JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION log_admin_action(UUID, TEXT, TEXT, UUID, TEXT, JSONB) FROM anon, authenticated;

-- ============================================================================
-- admin_suspend_user — auth · is_admin · reason 1..500 · not-self · target
-- exists · target NOT admin · set suspended_at · log.
-- ============================================================================
CREATE OR REPLACE FUNCTION admin_suspend_user(p_user_id UUID, p_reason TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_reason TEXT;
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_admin AND is_admin = true) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_reason := trim(coalesce(p_reason, ''));
  IF char_length(v_reason) < 1 OR char_length(v_reason) > 500 THEN
    RAISE EXCEPTION 'junto.admin_reason_required';
  END IF;

  IF p_user_id = v_admin THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_user_id) THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  -- An admin cannot suspend another admin — admin status is managed at SQL level.
  IF EXISTS (SELECT 1 FROM users WHERE id = p_user_id AND is_admin = true) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET suspended_at = now() WHERE id = p_user_id AND suspended_at IS NULL;

  PERFORM log_admin_action(v_admin, 'suspend_user', 'user', p_user_id, v_reason, NULL);
END;
$$;

REVOKE ALL ON FUNCTION admin_suspend_user(UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION admin_suspend_user(UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION admin_suspend_user(UUID, TEXT) TO authenticated;

-- ============================================================================
-- admin_unsuspend_user — auth · is_admin · reason · target exists & suspended ·
-- clear suspended_at · log. (Fills the "no unsuspend exists" gap.)
-- ============================================================================
CREATE OR REPLACE FUNCTION admin_unsuspend_user(p_user_id UUID, p_reason TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_reason TEXT;
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_admin AND is_admin = true) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  v_reason := trim(coalesce(p_reason, ''));
  IF char_length(v_reason) < 1 OR char_length(v_reason) > 500 THEN
    RAISE EXCEPTION 'junto.admin_reason_required';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE users SET suspended_at = NULL WHERE id = p_user_id;

  PERFORM log_admin_action(v_admin, 'unsuspend_user', 'user', p_user_id, v_reason, NULL);
END;
$$;

REVOKE ALL ON FUNCTION admin_unsuspend_user(UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION admin_unsuspend_user(UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION admin_unsuspend_user(UUID, TEXT) TO authenticated;

-- ============================================================================
-- admin_resolve_user — id → identity (audited lookup, no reason required).
-- ============================================================================
CREATE OR REPLACE FUNCTION admin_resolve_user(p_user_id UUID)
RETURNS TABLE(id UUID, display_name TEXT, email TEXT, tier TEXT, is_admin BOOLEAN, suspended_at TIMESTAMPTZ, created_at TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_admin AND is_admin = true) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM users u WHERE u.id = p_user_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM log_admin_action(v_admin, 'resolve_user', 'user', p_user_id, NULL, NULL);

  RETURN QUERY
    SELECT u.id, u.display_name, u.email, u.tier, u.is_admin, u.suspended_at, u.created_at
    FROM users u WHERE u.id = p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION admin_resolve_user(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION admin_resolve_user(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION admin_resolve_user(UUID) TO authenticated;

-- ============================================================================
-- admin_pro_owner — pro page (pro_profiles.user_id) → owner identity (audited).
-- ============================================================================
CREATE OR REPLACE FUNCTION admin_pro_owner(p_pro_id UUID)
RETURNS TABLE(pro_id UUID, pro_name TEXT, status TEXT, owner_display_name TEXT, owner_email TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_admin AND is_admin = true) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_profiles pp WHERE pp.user_id = p_pro_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM log_admin_action(v_admin, 'pro_owner', 'pro_profile', p_pro_id, NULL, NULL);

  RETURN QUERY
    SELECT pp.user_id, pp.display_name, pp.status, u.display_name, u.email
    FROM pro_profiles pp JOIN users u ON u.id = pp.user_id
    WHERE pp.user_id = p_pro_id;
END;
$$;

REVOKE ALL ON FUNCTION admin_pro_owner(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION admin_pro_owner(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION admin_pro_owner(UUID) TO authenticated;

-- ============================================================================
-- RETROFIT: existing admin functions now write to the audit log.
-- ============================================================================
CREATE OR REPLACE FUNCTION moderate_report(
  p_report_id UUID,
  p_action TEXT,
  p_admin_note TEXT DEFAULT NULL,
  p_suspend_user_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_report RECORD;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND is_admin = true) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_action NOT IN ('dismissed', 'actioned') THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  SELECT id, status INTO v_report FROM reports WHERE id = p_report_id;
  IF v_report IS NULL OR v_report.status != 'pending' THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  UPDATE reports
  SET status = p_action, admin_note = p_admin_note, resolved_at = now()
  WHERE id = p_report_id;

  IF p_suspend_user_id IS NOT NULL AND p_action = 'actioned' THEN
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE users SET suspended_at = now() WHERE id = p_suspend_user_id AND suspended_at IS NULL;
  END IF;

  PERFORM log_admin_action(
    v_user_id, 'moderate_report', 'report', p_report_id, p_admin_note,
    jsonb_build_object('action', p_action, 'suspended_user_id', p_suspend_user_id)
  );
END;
$$;

CREATE OR REPLACE FUNCTION approve_pro(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_admin AND is_admin = true) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = p_user_id AND status = 'pending') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE pro_profiles
    SET status = 'approved', rejection_reason = NULL, reviewed_at = now(), reviewed_by = v_admin
    WHERE user_id = p_user_id;
  UPDATE users SET tier = 'pro' WHERE id = p_user_id;

  INSERT INTO notifications (user_id, type, title, body, data)
  VALUES (p_user_id, 'pro_approved', 'Page pro validée',
          'Ta page pro est en ligne. Tu peux maintenant publier tes offres. 🎉',
          jsonb_build_object('pro_id', p_user_id));

  PERFORM log_admin_action(v_admin, 'approve_pro', 'pro_profile', p_user_id, NULL, NULL);
END;
$$;

CREATE OR REPLACE FUNCTION reject_pro(p_user_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
BEGIN
  v_admin := auth.uid();
  IF v_admin IS NULL THEN RAISE EXCEPTION 'Operation not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_admin AND is_admin = true) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pro_profiles WHERE user_id = p_user_id AND status = 'pending') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_reason IS NOT NULL AND char_length(p_reason) > 500 THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);
  UPDATE pro_profiles
    SET status = 'rejected', rejection_reason = NULLIF(trim(coalesce(p_reason, '')), ''),
        reviewed_at = now(), reviewed_by = v_admin
    WHERE user_id = p_user_id;

  INSERT INTO notifications (user_id, type, title, body, data)
  VALUES (p_user_id, 'pro_rejected', 'Demande pro refusée',
          coalesce(NULLIF(trim(coalesce(p_reason, '')), ''), 'Ta demande de page pro n''a pas été validée. Tu peux corriger tes informations et soumettre à nouveau.'),
          jsonb_build_object('pro_id', p_user_id));

  PERFORM log_admin_action(v_admin, 'reject_pro', 'pro_profile', p_user_id, NULLIF(trim(coalesce(p_reason, '')), ''), NULL);
END;
$$;
