-- Migration 00127: expose confirmed_present on the public_participants and
-- activity_participants views so the client can render a "validated" tick
-- next to participants whose presence has been confirmed.

DROP VIEW IF EXISTS public_participants;
CREATE VIEW public_participants AS
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
JOIN public_profiles pp ON pp.id = p.user_id;

GRANT SELECT ON public_participants TO authenticated;

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
  p.confirmed_present,
  p.transport_type,
  p.transport_seats,
  p.transport_from_name,
  p.transport_departs_at,
  a.creator_id,
  pp.display_name,
  pp.avatar_url,
  pp.sports,
  pp.levels_per_sport,
  reliability_tier(u.reliability_score) AS reliability_tier
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
