-- 00317: align the activities SELECT policy with get_activity_detail
--
-- 00316 tightened get_activity_detail's participation gate to
-- accepted/pending but left the table policy's participant branch
-- status-unfiltered — so a removed/refused member could still read the
-- base activities row (invite_token included) via a direct PostgREST
-- query even though the detail RPC now blocks them. Counter-audit
-- (2026-07-10) flagged the inconsistency; Scott validated the alignment.
-- The participant branch now matches: only accepted/pending see private
-- rows they belong to. Public/approval rows stay open via the
-- discoverable branch regardless.

DROP POLICY IF EXISTS "activities_select_authenticated" ON activities;

CREATE POLICY "activities_select_authenticated"
  ON activities FOR SELECT
  TO authenticated
  USING (
    NOT private.user_is_suspended(auth.uid())
    AND (
      (
        status IN ('published', 'in_progress')
        AND deleted_at IS NULL
        AND visibility IN ('public', 'approval')
        AND NOT private.user_is_suspended(activities.creator_id)
        AND creator_id NOT IN (
          SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid()
        )
      )
      OR auth.uid() = creator_id
      OR EXISTS (
        SELECT 1 FROM participations
        WHERE activity_id = activities.id
          AND user_id = auth.uid()
          AND status IN ('accepted', 'pending')
      )
    )
  );
