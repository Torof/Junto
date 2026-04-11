-- Migration 00017: restrict activities SELECT to hide invite_token from anon
-- Problem: anon can query activities table directly and read invite_token
-- Fix: drop the open SELECT policy, create separate policies for anon (no invite_token access)
-- Anon should use activities_with_coords view (which excludes invite_token)

-- Drop the existing permissive SELECT policy
DROP POLICY IF EXISTS "activities_select_discovery" ON activities;

-- Authenticated users: full row access (same conditions as before)
CREATE POLICY "activities_select_authenticated"
  ON activities FOR SELECT
  TO authenticated
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

-- Anon: NO direct SELECT on activities table
-- Anon accesses activities via activities_with_coords view only (GRANT already exists)
-- The view is owned by postgres and bypasses RLS, so anon can still see activities through it
