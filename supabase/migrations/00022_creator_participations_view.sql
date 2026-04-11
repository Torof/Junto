-- Migration 00022: view for creator to see all participations for their activities
-- Avoids the RLS recursion issue (no cross-table policy reference)

CREATE VIEW activity_participants AS
SELECT
  p.id AS participation_id,
  p.activity_id,
  p.user_id,
  p.status,
  p.created_at,
  p.left_at,
  a.creator_id,
  pp.display_name,
  pp.avatar_url
FROM participations p
JOIN activities a ON a.id = p.activity_id
JOIN public_profiles pp ON pp.id = p.user_id
WHERE a.creator_id = auth.uid()
  AND p.user_id != a.creator_id;

GRANT SELECT ON activity_participants TO authenticated;
