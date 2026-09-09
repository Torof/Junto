-- ============================================================================
-- 00412 — Audit 2nd pass, phase 4 (LOW): transfer created channels on account
-- deletion instead of orphaning them.
--
-- channels.created_by is ON DELETE SET NULL, so deleting a channel creator left
-- created_by NULL → every creator-gated RPC then denied everyone → the channel
-- stayed open, joinable and unmoderated forever. Scott's choice: transfer to the
-- earliest remaining member. Done inside delete_own_account BEFORE the user row
-- is deleted (already under bypass_lock), so the created_by FK no longer touches
-- these rows and there's no whitelist-trigger/cascade conflict. Channels with no
-- other member are closed (harmless — empty). (Scott 2026-09-09, 2nd adv. pass.)
-- ============================================================================

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
  v_channel RECORD;
  v_new_owner UUID;
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

  -- 2b. Channels created by the user: hand the hub to the earliest remaining
  -- member so it keeps a moderator; if none remain, close it. Before the user
  -- delete so the created_by FK no longer references these rows.
  FOR v_channel IN
    SELECT conversation_id FROM channels WHERE created_by = v_user_id
  LOOP
    SELECT user_id INTO v_new_owner
    FROM conversation_members
    WHERE conversation_id = v_channel.conversation_id AND user_id != v_user_id
    ORDER BY joined_at ASC
    LIMIT 1;

    IF v_new_owner IS NOT NULL THEN
      UPDATE channels SET created_by = v_new_owner WHERE conversation_id = v_channel.conversation_id;
      UPDATE conversations SET created_by = v_new_owner WHERE id = v_channel.conversation_id;
    ELSE
      UPDATE channels SET closed_at = now()
      WHERE conversation_id = v_channel.conversation_id AND closed_at IS NULL;
    END IF;
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
