-- Migration 00196: minimum-viable auth chain on get_transport_summary.
--
-- Audit pass 1 finding I-2: 00075 created get_transport_summary as a
-- SECURITY DEFINER function with NO auth chain — any authenticated
-- user could call it on any activity_id and read transport mode
-- counts + seat totals + the cities of accepted participants.
-- Touched private activities, deleted activities, served suspended
-- callers.
--
-- Why we don't gate to accepted-participant:
-- The function is consumed by the activity Info tab (see
-- activity-detail.tsx transportSummary block), which is visible to
-- non-participants browsing an activity card. Tightening to
-- participants-only would regress that UX. The realistic leak
-- surface is the `cities` array (DISTINCT transport_from_name
-- aggregated by mode) — already capped at 100 chars per entry by
-- the column CHECK and contributed deliberately by users.
--
-- This migration adds the smallest hardening that closes the audit
-- gap without changing UX:
--   1. auth.uid() not null — make the implicit GRANT-to-authenticated
--      explicit so the bail is visible at the function level too.
--   2. caller not suspended — consistent with other RPCs.
--   3. activity exists, status ∈ {published, in_progress}, not
--      soft-deleted — closes the deleted-activity / closed-activity
--      replay window.
--
-- If the desired posture later shifts to "participants-only", swap
-- the activity check for a participations join and update the Info
-- tab accordingly.

CREATE OR REPLACE FUNCTION get_transport_summary(
  p_activity_id UUID
)
RETURNS TABLE (
  transport_type TEXT,
  count INTEGER,
  total_seats INTEGER,
  cities TEXT[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND suspended_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM activities
    WHERE id = p_activity_id
      AND status IN ('published', 'in_progress')
      AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Operation not permitted';
  END IF;

  RETURN QUERY
  SELECT
    p.transport_type,
    count(*)::int AS count,
    COALESCE(sum(p.transport_seats)::int, 0) AS total_seats,
    array_agg(DISTINCT p.transport_from_name) FILTER (WHERE p.transport_from_name IS NOT NULL) AS cities
  FROM participations p
  WHERE p.activity_id = p_activity_id
    AND p.status = 'accepted'
    AND p.transport_type IS NOT NULL
  GROUP BY p.transport_type
  ORDER BY count DESC;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_transport_summary FROM anon;
GRANT EXECUTE ON FUNCTION get_transport_summary TO authenticated;
