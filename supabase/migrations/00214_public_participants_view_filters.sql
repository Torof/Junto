-- Migration 00214: restore public_participants filters + security_invoker.
-- Closes group C from the parallel security audit.
--
-- Background: 00040 created the view with two filters at the view
-- level:
--   WHERE p.status = 'accepted'
--     AND p.user_id NOT IN (SELECT blocked_id FROM blocked_users
--                           WHERE blocker_id = auth.uid())
--
-- Both filters were silently dropped in 00112 / 00127 when the view
-- was rebuilt to expose new transport / presence columns. Since
-- views run as their owner unless declared `security_invoker`, the
-- view also bypassed `participations` RLS — meaning every authenticated
-- user could read every participation row of every activity in any
-- status (pending, refused, withdrawn, removed) and across blocks.
--
-- Fix:
--  1. Re-add the two WHERE filters.
--  2. Set `security_invoker = on` so the participations SELECT policy
--     re-applies as a second line of defence — if a future bug
--     accidentally drops the view-level filter, RLS still gates rows
--     to (own row | creator | accepted-participant of same activity).
--
-- Consumer expectation matches: every caller of the view via
-- transport-service.getForActivity / participation-service.getForActivity
-- expects accepted-only rows. Pending participations are queried via
-- the separate `activity_participants` view (creator-scoped) by
-- participation-service.getPendingForActivity.

CREATE OR REPLACE VIEW public_participants
WITH (security_invoker = on) AS
SELECT
  p.id AS participation_id,
  p.activity_id,
  p.user_id,
  p.status,
  p.created_at,
  p.left_at,
  p.confirmed_present,
  p.transport_type,
  p.transport_seats,
  p.transport_from_name,
  p.transport_departs_at,
  pp.display_name,
  pp.avatar_url
FROM participations p
JOIN public_profiles pp ON pp.id = p.user_id
WHERE p.status = 'accepted'
  AND p.user_id NOT IN (
    SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid()
  );

GRANT SELECT ON public_participants TO authenticated;
