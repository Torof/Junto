-- Migration 00042: Account deletion function
-- Handles all data cleanup per SECURITY.md deletion strategy
-- auth.users row cleaned up manually by admin (requires service_role)

CREATE OR REPLACE FUNCTION delete_own_account()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_activity RECORD;
  v_participant RECORD;
BEGIN
  -- 1. Auth check
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  PERFORM set_config('junto.bypass_lock', 'true', true);

  -- 2. Cancel all active activities created by user + notify participants
  FOR v_activity IN
    SELECT id, title FROM activities
    WHERE creator_id = v_user_id AND status IN ('published', 'in_progress')
  LOOP
    UPDATE activities SET status = 'cancelled', updated_at = now() WHERE id = v_activity.id;

    FOR v_participant IN
      SELECT user_id FROM participations
      WHERE activity_id = v_activity.id AND status = 'accepted' AND user_id != v_user_id
    LOOP
      PERFORM create_notification(
        v_participant.user_id,
        'activity_cancelled',
        'Activité annulée',
        v_activity.title || ' a été annulée',
        jsonb_build_object('activity_id', v_activity.id)
      );
    END LOOP;
  END LOOP;

  -- 3. Wall messages: anonymize (SET NULL handled by FK ON DELETE SET NULL)
  -- 4. Private messages: deleted by FK ON DELETE CASCADE
  -- 5. Conversations: deleted by FK ON DELETE CASCADE
  -- 6. Participations: deleted by FK ON DELETE CASCADE
  -- 7. Notifications: deleted by FK ON DELETE CASCADE
  -- 8. Blocked users: deleted by FK ON DELETE CASCADE
  -- 9. Reputation votes: deleted by FK ON DELETE CASCADE
  -- 10. Reports: kept (no FK CASCADE — moderation history survives)

  -- 11. Delete the user row — FKs handle cascading
  DELETE FROM users WHERE id = v_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION delete_own_account FROM anon;
GRANT EXECUTE ON FUNCTION delete_own_account TO authenticated;
