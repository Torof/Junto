-- Migration 00005: deferred RLS policies
-- These policies reference tables created in previous migrations (cross-table dependencies)

-- ============================================================================
-- ACTIVITIES SELECT policy (needs: participations, blocked_users)
-- ============================================================================
CREATE POLICY "activities_select_discovery"
  ON activities FOR SELECT
  USING (
    (
      status IN ('published', 'in_progress')
      AND deleted_at IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM users WHERE id = activities.creator_id AND suspended_at IS NOT NULL
      )
      AND creator_id NOT IN (
        SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid()
      )
    )
    OR creator_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM participations
      WHERE activity_id = activities.id AND user_id = auth.uid()
    )
  );
