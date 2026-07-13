-- Migration 00322: admin content takedown (Batch 2, part 2)
--
-- docs/ADMIN.md charter. Lets an admin remove abusive PUBLIC/reviewable content
-- flagged by a report: an activity, a wall message, or a pro/offering review.
-- Reason-bound and audited (admin_actions).
--
-- Boundary enforced: private messages are NEVER actionable here (charter — an
-- admin never touches DMs; a DM report is handled by suspending the user, with
-- evidence attached by the reporter). Users aren't removed here either — that's
-- admin_suspend_user. So the accepted target types are exactly:
-- activity / wall_message / pro_review / offering_review.

CREATE OR REPLACE FUNCTION admin_remove_content(
  p_target_type TEXT,
  p_target_id UUID,
  p_reason TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_reason TEXT;
  v_found BOOLEAN := false;
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

  -- Only public/reviewable content. private_message and user are rejected here.
  IF p_target_type NOT IN ('activity', 'wall_message', 'pro_review', 'offering_review') THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  IF p_target_type = 'activity' THEN
    UPDATE activities SET deleted_at = now(), updated_at = now()
    WHERE id = p_target_id AND deleted_at IS NULL;
    v_found := FOUND;
  ELSIF p_target_type = 'wall_message' THEN
    UPDATE wall_messages SET deleted_at = now()
    WHERE id = p_target_id AND deleted_at IS NULL;
    v_found := FOUND;
  ELSIF p_target_type = 'pro_review' THEN
    DELETE FROM pro_reviews WHERE id = p_target_id;
    v_found := FOUND;
  ELSIF p_target_type = 'offering_review' THEN
    DELETE FROM offering_reviews WHERE id = p_target_id;
    v_found := FOUND;
  END IF;

  IF NOT v_found THEN RAISE EXCEPTION 'Operation not permitted'; END IF;

  PERFORM log_admin_action(v_admin, 'remove_content', p_target_type, p_target_id, v_reason, NULL);
END;
$$;

REVOKE ALL ON FUNCTION admin_remove_content(TEXT, UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION admin_remove_content(TEXT, UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION admin_remove_content(TEXT, UUID, TEXT) TO authenticated;
