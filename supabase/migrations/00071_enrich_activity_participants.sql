-- Migration 00071: enrich activity_participants view with reliability + sports
-- So creators can evaluate join requests at a glance without navigating away.

DROP VIEW IF EXISTS activity_participants;

CREATE VIEW activity_participants AS
SELECT
  p.id AS participation_id,
  p.activity_id,
  p.user_id,
  p.status,
  p.created_at,
  p.left_at,
  p.left_reason,
  p.penalty_waived,
  a.creator_id,
  pp.display_name,
  pp.avatar_url,
  pp.sports,
  pp.levels_per_sport,
  u.reliability_score
FROM participations p
JOIN activities a ON a.id = p.activity_id
JOIN public_profiles pp ON pp.id = p.user_id
JOIN users u ON u.id = p.user_id
WHERE a.creator_id = auth.uid()
  AND p.user_id != a.creator_id
  AND p.status != 'removed'
  AND a.deleted_at IS NULL
  AND p.user_id NOT IN (
    SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid()
  );

GRANT SELECT ON activity_participants TO authenticated;
