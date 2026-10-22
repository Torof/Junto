-- Migration 00040: Public participants view
-- Shows accepted participants for any activity, visible to all authenticated users
-- Excludes blocked users (unidirectional)

CREATE VIEW public_participants AS
SELECT
  p.id AS participation_id,
  p.activity_id,
  p.user_id,
  p.status,
  p.created_at,
  pp.display_name,
  pp.avatar_url
FROM participations p
JOIN public_profiles pp ON pp.id = p.user_id
WHERE p.status = 'accepted'
  AND p.user_id NOT IN (
    SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid()
  );

GRANT SELECT ON public_participants TO authenticated;
