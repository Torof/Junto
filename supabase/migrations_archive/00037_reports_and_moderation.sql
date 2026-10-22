-- Migration 00037: Reports table + moderation functions

-- ============================================================================
-- TABLE: reports
-- ============================================================================
CREATE TABLE reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id UUID NOT NULL REFERENCES users(id),
  target_type TEXT NOT NULL CHECK (target_type IN ('user', 'activity', 'wall_message', 'private_message')),
  target_id UUID NOT NULL,
  reason TEXT NOT NULL CHECK (char_length(reason) BETWEEN 10 AND 1000),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'dismissed', 'actioned')),
  admin_note TEXT,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
  resolved_at TIMESTAMPTZ
);

CREATE INDEX idx_reports_status ON reports(status);
CREATE INDEX idx_reports_reporter ON reports(reporter_id);

ALTER TABLE reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE reports FORCE ROW LEVEL SECURITY;

-- Reporter sees own reports + admins see all
CREATE POLICY "reports_select"
  ON reports FOR SELECT
  TO authenticated
  USING (
    reporter_id = auth.uid()
    OR EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND is_admin = true)
  );

-- UPDATE: admins only (change status)
CREATE POLICY "reports_update_admin"
  ON reports FOR UPDATE
  TO authenticated
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND is_admin = true))
  WITH CHECK (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND is_admin = true));

-- INSERT/DELETE: via function only (no direct client insert to prevent spam)

-- ============================================================================
-- FUNCTION: create_report (rate limited, validated)
-- ============================================================================
CREATE OR REPLACE FUNCTION create_report(
  p_target_type TEXT,
  p_target_id UUID,
  p_reason TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_report_id UUID;
  v_hourly_count INTEGER;
BEGIN
  -- 1. Auth check
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 2. Suspension check
  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 3. Valid target type
  IF p_target_type NOT IN ('user', 'activity', 'wall_message', 'private_message') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 4. Reason length
  IF char_length(trim(p_reason)) < 10 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 5. Can't report yourself
  IF p_target_type = 'user' AND p_target_id = v_user_id THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 6. Target exists
  IF p_target_type = 'user' AND NOT EXISTS (SELECT 1 FROM users WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_target_type = 'activity' AND NOT EXISTS (SELECT 1 FROM activities WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_target_type = 'wall_message' AND NOT EXISTS (SELECT 1 FROM wall_messages WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;
  IF p_target_type = 'private_message' AND NOT EXISTS (SELECT 1 FROM private_messages WHERE id = p_target_id) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 7. No duplicate report on same target
  IF EXISTS (
    SELECT 1 FROM reports
    WHERE reporter_id = v_user_id AND target_type = p_target_type AND target_id = p_target_id
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 8. Rate limit: 10 reports per hour
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text || '_reports'));

  SELECT count(*) INTO v_hourly_count
  FROM reports
  WHERE reporter_id = v_user_id AND created_at > NOW() - INTERVAL '1 hour';

  IF v_hourly_count >= 10 THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 9. Insert report
  INSERT INTO reports (reporter_id, target_type, target_id, reason, status, created_at)
  VALUES (v_user_id, p_target_type, p_target_id, trim(p_reason), 'pending', now())
  RETURNING id INTO v_report_id;

  RETURN v_report_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_report FROM anon;
GRANT EXECUTE ON FUNCTION create_report TO authenticated;

-- ============================================================================
-- FUNCTION: moderate_report (admin only — dismiss or action + optional suspend)
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
  -- 1. Auth check
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 2. Must be admin
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND is_admin = true) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 3. Valid action
  IF p_action NOT IN ('dismissed', 'actioned') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 4. Report exists and is pending
  SELECT id, status INTO v_report FROM reports WHERE id = p_report_id;
  IF v_report IS NULL OR v_report.status != 'pending' THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  -- 5. Update report
  UPDATE reports
  SET status = p_action, admin_note = p_admin_note, resolved_at = now()
  WHERE id = p_report_id;

  -- 6. Optionally suspend user
  IF p_suspend_user_id IS NOT NULL AND p_action = 'actioned' THEN
    PERFORM set_config('junto.bypass_lock', 'true', true);
    UPDATE users SET suspended_at = now() WHERE id = p_suspend_user_id AND suspended_at IS NULL;
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION moderate_report FROM anon;
GRANT EXECUTE ON FUNCTION moderate_report TO authenticated;
