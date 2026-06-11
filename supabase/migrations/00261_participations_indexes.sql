-- Migration 00261: activity-side indexes on participations.
--
-- Prod-readiness audit D (2026-06-11): the table's only index is the
-- implicit UNIQUE (user_id, activity_id) — user-leading, useless for
-- the hottest read paths which all enter by activity_id:
--   - participant lists (WHERE activity_id = ? AND status = 'accepted')
--   - join-state checks (WHERE activity_id = ? AND user_id = ?)
--   - the per-row participant_count subquery in activities_with_coords,
--     executed once per activity row on every map/list fetch.
-- Without these, every map render does sequential scans of
-- participations once per visible activity.

CREATE INDEX IF NOT EXISTS participations_activity_status_idx
  ON participations(activity_id, status);

CREATE INDEX IF NOT EXISTS participations_activity_user_idx
  ON participations(activity_id, user_id);
